/**
*********************************************************************************
* Copyright Since 2005 ColdBox Framework by Luis Majano and Ortus Solutions, Corp
* www.ortussolutions.com
* ---
* RabbitMQ Client.  This is a singleton that represents a single connection to Rabbit.
* Only create me once and ask me to create channels for every new thread that wants to interact with the server.
* ALWAYS make sure you call the shutdown() method when you're done using or you'll leave orphaned connections open.
*/
component accessors=true singleton {
	
	// DI
	property name="settings" inject="coldbox:moduleSettings:rabbitsdk";
	property name="wirebox" inject="wirebox";
	property name="moduleConfig" inject="coldbox:moduleConfig:rabbitsdk";
	property name="controller" inject="coldbox";
//	property name="javaloader" inject="loader@cbjavaloader";
	property name="log" inject="logbox:logger:{this}";
	

	/** The RabbitMQ Connection */
	property name="connection" type="any";
	property name="clientID" type="string";
	
	/**
	 * Constructor
	 */
	function init(){
		setClientID( createUUID() );
		return this;
	}
	
	function onDIComplete(){
		controller.getInterceptorService().registerInterceptor( 
			interceptorObject 	= this,
			interceptorName 	= "rabbitsdk-client-#getClientID()#"
		);
	}

	/**
	 * @host The host such as "localhost"
	 * @port The port to connect on 
	 * @username The username to connect with
	 * @password The password to connect with
	 * @quiet True to ignore existing connections, false will throw an exception if there is already a connection
	 * 
	 * Create connection to RabbitMQ.  This will be called implicitly if the
	 * connection details have been provided in the module settings.
	 * This RabbitClient wraps a single, persisted conenction to RabbitMQ.
	 */
	function connect( string host, string port, string username, string password, string virtualHost, boolean useSSL, boolean quiet=false ){
		
		if( hasConnection() ) {
			if( quiet ) {
				return this;
			}
			throw( 'Client is already connected.' );
		}
		
		lock timeout="20" type="exclusive" name="RabbitMQConnect" {
			    
			if( hasConnection() ) {
				if( quiet ) {
					return this;
				}
				throw( 'Client is already connected.' );
			}
			var thisHost = arguments.host ?: settings.host ?: '';
			var thisUsername = arguments.username ?: settings.username ?: '';
			var thisPassword = arguments.password ?: settings.password ?: '';
			var thisPort = arguments.port ?: settings.port ?: '';
			var thisVirtualHost = arguments.virtualHost ?: settings.virtualHost ?: '';
			var thisUseSSL= arguments.useSSL ?: settings.useSSL ?: '';
			
			
			if( !thisHost.len() && !thisUsername.len() ) {
				throw( 'No Rabbit Host and username configured.  Cannot connect.' );
			}
			
			log.debug( 'Creating connection to [#thisHost#]' );
			
			//var factory = javaloader.create( "com.rabbitmq.client.ConnectionFactory" ).init();
			var factory = createObject( "java", "com.rabbitmq.client.ConnectionFactory" ).init();
			factory.setHost( thisHost );
			factory.setUsername( thisUsername );
			factory.setPassword( thisPassword );
			
			if( isBoolean( thisUseSSL ) ) {
				factory.useSslProtocol( thisUseSSL );	
			}
			
			if( len( thisVirtualHost ) ) {
				factory.setVirtualHost( thisVirtualHost );	
			}
			
			factory.setRequestedHeartbeat( 20 );
			if( val( thisPort ) != 0 ) {
				factory.setPort( thisPort );	
			}			
			setConnection( factory.newConnection() );
			
		}
		return this;
	}

	/**
	 * All communication with Rabbit happens over a channel.  There are two simple rules for channels.
	 * - Create a fresh channel for each request
	 * - Call channel.close() when you're done with it so resources are freed.
	 */
	function createChannel() {
		// Try to connect if we're not connected already
		connect( quiet=true );
		return wirebox.getInstance( 'channel@rabbitsdk' )
			.setConnection( getConnection() )
			.configure();
	}

	/**
	 * Creates an auto-closing channel for multuple operations.  Do not store the channel refernce passed to the callback
	 * as it will be closed as soon as the UDF is finished.  Any value returned from the UDF will be returned from the
	 * batch method.  
	 * This allows you to not need to worry about closing the channel.  Also, if you have a large number of operations to 
	 * perform on the channel, you can perform them all inside your UDF.
	 */
	function batch( required any udf ) {
		try {
			var channel = createChannel();
			return udf( channel ); 
		} finally {
			if( !isNull( channel ) ) {
				channel.close();
			}
		}
	}

	/**
	 * Listen to the ColdBox app reinitting or shutting down
	 */
	function preReinit() {
		log.debug( 'Framework shutdown detected.' );
		shutdown();
	}

	/**
	 * Call this when the app shuts down or reinits.
	 * This is very important so that orphaned connections are not left in memory
	 */
	function shutdown() {
		lock timeout="20" type="exclusive" name="RabbitMQShutdown" {
			log.debug( 'Shutting down RabbitMQ client' );
			if( hasConnection() ) {
				getConnection().close();
				structDelete( variables, 'connection' );
			}
			controller.getInterceptorService().unregister( "rabbitsdk-client-#getClientID()#" );
		}
	}

	/**
	 * Return true if client has connection to RabbitMQ Server.
	 */
	boolean function hasConnection() {
		return !isNull( variables.connection );
	}
	
	
	// CONVEIENCE METHODS THAT AUTOMATICALLY HANDLE YOUR CHANNEL FOR YOU
	
	
	
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
		var args = arguments;
		batch( (channel)=>channel.queueDeclare( argumentCollection=args ) );
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
		var args = arguments;
		batch( (channel)=>channel.queueDelete( argumentCollection=args ) );
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
		var args = arguments;
		batch( (channel)=>channel.queueBind( argumentCollection=args ) );
		return this;
	}
	
	/**
	* @queue the name of the queue
	* 
	* Purges the contents of the given queue.
	*/
	function queuePurge( required string queue ) {
		var args = arguments;
		batch( (channel)=>channel.queuePurge( argumentCollection=args ) );
		return this;
	}
	
	/**
	* @queue the name of the queue
	* 
	* Returns count of the messages of the given queue.
	* Doesn't count messages which waiting acknowledges or published to queue during transaction but not committed yet.
	*/
	function getQueueMessageCount( required string queue ) {
		var args = arguments;
		return batch( (channel)=>channel.getQueueMessageCount( argumentCollection=args ) );
	}
	
	/**
	* @queue the name of the queue
	* 
	* Returns true if queue exists, false if it doesn't.  Be careful calling this method under load as it 
	* catches a thrown exception if the queue doesn't exist so it probably doesn't perform great if the queue you
	* are checking doesn't exist most of the time.
	*/
	boolean function queueExists( required string queue ) {
		var args = arguments;
		return batch( (channel)=>channel.queueExists( argumentCollection=args ) );
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
		var args = arguments;
		batch( (channel)=>channel.publish( argumentCollection=args ) );
		return this;
	}
	
	/**
	* @queue the name of the queue
	*
	* Get a single message from a queue.  If there are no messages in the queue, null will be returned.
	*/
	function getMessage(
		required string queue
	) {
		if( !isNull( arguments.autoAcknowledge ) && !arguments.autoAcknowledge ) {
			throw( 'autoAcknowledge cannot be set to false in this method.  Messages must be acknowledged on the same channel they were received.  Please create a channel and use its getMessage() method or use the rabbitClient.batch() method.' );
		}
		
		var args = arguments;
		return batch( (channel)=> channel.getMessage( argumentCollection=args ) );
	}
	
	/**
	* @queue Name of the queue to consume
	* @consumer A UDF or CFC to consume messages
	* @method Name of method to call when 'consumer' argument is a CFC. Default is onMessage()
	* @autoAcknowledge Automatically ackowledge each message as processed
	* @prefetch Number of messages this consumer should fetch at once. 0 for unlimited
	*/
	function startConsumer(
		required string queue,
		any consumer,
		string method='onMessage',
		boolean autoAcknowledge=true,
		numeric prefetch=1
	) {
		var args = arguments;
		return batch( (channel)=>channel.startConsumer( argumentCollection=args ) );
	}
	
}