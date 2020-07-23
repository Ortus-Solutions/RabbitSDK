/**
* This is a transient that represents a channel of communication over an existing 
* Do not re-use the same channel across more than one thread.  MAKE SURE you close 
* this channel when you're finished with it so so the resources aren't left open.
*/
component accessors="true"  {

	// DI
//	property name="javaloader" inject="loader@cbjavaloader";
	property name="wirebox" inject="wirebox";
		
	/** The RabbitMQ Connection this channel belongs to */
	property name="connection" type="any";
	/** The RabbitMQ Channel object */
	property name="channel" type="any";
	property name="messagePropertiesBuilder" type="any";
	property name="javaUtilDate" type="any";
	property name="consumerTag" type="string" default="";
	
	/**
	* configure a new channel
	*/
	function configure() {
		setConsumerTag( '' );
		setChannel( getConnection().createChannel() );
		//setMessagePropertiesBuilder( javaloader.create( "com.rabbitmq.client.AMQP$BasicProperties$Builder" ) );
		setMessagePropertiesBuilder( createObject( "java", "com.rabbitmq.client.AMQP$BasicProperties$Builder" ) );
		setJavaUtilDate( createObject( 'java', 'java.util.Date' ) );
		return this;
	}
	
	/**
	* @name the name of the queue
	* @durable true if we are declaring a durable queue (the queue will survive a server restart)
	* @exclusive true if we are declaring an exclusive queue (restricted to this connection)
	* @autoDelete true if we are declaring an autodelete queue (server will delete it when no longer in use)
	* @queueArguments  Struct of other properties (construction arguments) for the queue
	* 
	* Declare a new quueue.  Nothing happens if this queue already exists.
	*/
	function queueDeclare(
		required string name,
		boolean durable=false,
		boolean exclusive=false,
		boolean autoDelete=false,
		struct queueArguments={}
	) {
		getChannel().queueDeclare( name, durable, exclusive, autoDelete, queueArguments );
		return this;
	}
	
	/**
	* @name the name of the queue
	* @ifUnused true if the queue should be deleted only if not in use
	* @ifEmpty true if the queue should be deleted only if empty
	* Delete a queue
	*/
	function queueDelete(
		required string name,
		boolean ifUnused=false,
		boolean ifEmpty=false
	) {
		getChannel().queueDelete( name, ifUnused, ifEmpty );
		return this;
	}
	
	
	/**
	* @queue the name of the queue
	* @exchange the name of the exchange
	* @routingKey the routing key to use for the binding
	* @bindArguments Struct of other properties (binding parameters)
	* 
	* Bind a queue to an exchange.
	*/
	function queueBind(
		required string queue,
		required string exchange,
		required string routingKey,
		struct bindArguments={}
	) {
		getChannel().queueBind( queue, exchange, routingKey, bindArguments );
		return this;
	}
	
	/**
	* @queue the name of the queue
	* 
	* Purges the contents of the given queue.
	*/
	function queuePurge( required string queue ) {
		getChannel().queuePurge( queue );
		return this;
	}
	
	/**
	* @queue the name of the queue
	* 
	* Returns count of the messages of the given queue.
	* Doesn't count messages which waiting acknowledges or published to queue during transaction but not committed yet.
	*/
	function getQueueMessageCount( required string queue ) {
		// https://www.rabbitmq.com/releases/rabbitmq-java-client/v3.5.4/rabbitmq-java-client-javadoc-3.5.4/com/rabbitmq/client/AMQP.Queue.DeclareOk.html
		var DeclareOk = getChannel().queueDeclarePassive( queue );
		return DeclareOk.getMessageCount();
	}
	
	/**
	* @queue the name of the queue
	* 
	* Returns true if queue exists, false if it doesn't.  Be careful calling this method under load as it 
	* catches a thrown exception if the queue doesn't exist so it probably doesn't perform great if the queue you
	* are checking doesn't exist most of the time.
	*/
	boolean function queueExists( required string queue ) {
		try {
			var DeclareOk = getChannel().queueDeclarePassive( queue );
		} catch( any var e ) {
			// Any error on a channel closes it, so create a fresh channel to keep working with
			setChannel( getConnection().createChannel() );
			// TODO: getPageException() is likely Lucee specific. Check for Adobe equivalent
			if( e.getPageException().getRootCause().getMessage() contains 'reply-code=404' ) {
				return false;
			}
			rethrow;
		}
		// This check is probably unecccessary since I don't any scenario where the call above doesn't error
		// but returns some other queue name, but it seems like a good measure to take.
		if( queue == DeclareOK.getQueue() ) {
			return true;
		}
		return false;
	}
	
	/**
	* @body The body of the message. Either a string or a complex object which will be JSON serialized.
	* @exchange the name of the exchange
	* @routingKey case sensitive routing key to use for the binding
	* @props Struct of other properties for the message - routing headers etc
	* 
	* Publish a message
	*/
	function publish(
		required any body,
		required string routingKey,
		string exchange='',
		struct props={}
	) {
		var propBuilder = getMessagePropertiesBuilder().init();
		
		if( !isSimpleValue( body ) ) {
			body = serializeJSON( body );
			props.headers = props.headers ?: {};
			props.headers[ '_autoJSON' ] = true;
		}
		
		props.each( (k,v) => {
			switch( k ) {
				case 'appId':
					propBuilder.appId( v );
					break;
				case 'clusterId':
					propBuilder.clusterId( v );
					break;
				case 'contentEncoding':
					propBuilder.contentEncoding( v );
					break;
				case 'contentType':
					propBuilder.contentType( v );
					break;
				case 'correlationId':
					propBuilder.correlationId( v );
					break;
				case 'deliveryMode':
					// TODO: Convert text delivery mode to integer
					propBuilder.deliveryMode( val( v ) );
					break;
				case 'expiration':
					propBuilder.expiration( v );
					break;
				case 'headers':
					propBuilder.headers( v );
					break;
				case 'messageId':
					propBuilder.messageId( v );
					break;
				case 'priority':
					propBuilder.priority( val( v ) );
					break;
				case 'replyTo':
					propBuilder.replyTo( v );
					break;
				case 'timestamp':
					if( isDate( v ) ) {
						propBuilder.timestamp( javaUtilDate.init( dateTimeFormat( v, 'mm/dd/yyyy HH:NN:SS' ) ) );
						break;	
					}
					throw( 'Invalid message property timestamp [#v#]' );
				case 'type':
					propBuilder.type( v );
					break;
				case 'userId':
					propBuilder.userId( v );
					break;
				default:
					throw( 'Unknown AMQP property [#k#]' );
					break;
			}
		} );
		
		getChannel().basicPublish( exchange, routingKey, propBuilder.build(), body.getBytes() );
		return this;
	}
	
	/**
	* @queue the name of the queue
	* @autoAcknowledge true if the server should consider messages acknowledged once delivered; false if the server should expect explicit acknowledgements
	*
	* Get a single message from a queue.  If there are no messages in the queue, null will be returned.
	*/
	function getMessage(
		required string queue,
		boolean autoAcknowledge=true
	) {
		var response = getChannel().basicGet( queue, autoAcknowledge );
		if( isNull( response ) ) {
			return;
		}
		// https://www.rabbitmq.com/releases/rabbitmq-java-client/v3.5.4/rabbitmq-java-client-javadoc-3.5.4/com/rabbitmq/client/GetResponse.html
		return wirebox.getInstance( 'message@rabbitsdk' )
			.setChannel( getChannel() )
			.setConnection( getConnection() )
			.populate( response.getEnvelope(), response.getProps(), response.getBody() );
	}
	
	/**
	* @queue Name of the queue to consume
	* @autoAcknowledge Automatically ackowledge each message as processed
	* @prefetch Number of messages this consumer should fetch at once. 0 for unlimited
	*/
	function startConsumer(
		required string queue,
		any udf,
		boolean autoAcknowledge=true,
		numeric prefetch=1,
		name=''
	) {
		if( getConsumerTag().len() ) {
			throw( 'This channel already has a running consumer. Please create a new channel or stop this channel''s consumer with stopConsumer().' );
		}
		
		var consumer = createDynamicProxy(
			wirebox.getInstance( name='consumer@rabbitsdk', initArguments={ channel : this, udf : udf } ),
			//[ javaloader.create( "com.rabbitmq.client.Consumer" ) ]
			[ createObject( "java", "com.rabbitmq.client.Consumer" ) ]
		);
		
		getChannel().basicQos( prefetch );
		setConsumerTag( getChannel().basicConsume( queue, autoAcknowledge, consumer ) );
		return this;		
	}
	
	/**
	* Stop a running consumer
	*/
	function stopConsumer() {
		
		if( !getConsumerTag().len() ) {
			throw( 'There is no consumer currenlty running on this channel.  Nothing to stop.' );
		}
		
		getChannel().basicCancel( getConsumerTag() );
		setConsumerTag( '' );
		
		return this;		
	}
	
	/**
	* Call this method for every channel when you are finished using it to free resources
	*/
	function close() {
		getChannel().close();
		return this;
	}

}