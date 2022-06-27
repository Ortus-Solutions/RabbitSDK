/**
*********************************************************************************
* Copyright Since 2005 ColdBox Framework by Luis Majano and Ortus Solutions, Corp
* www.ortussolutions.com
* ---
* RabbitMQ Client.  This is a singleton that represents a single connection to Rabbit.
* Only create me once and ask me to create channels for every new thread that wants to interact with the server.
* ALWAYS make sure you call the shutdown() method when you're done using or you'll leave orphaned connections open.
*/
component accessors=true singleton ThreadSafe {
	
	// DI
	property name="settings" inject="box:moduleSettings:rabbitsdk";
	property name="wirebox" inject="wirebox";
	property name="moduleConfig" inject="box:moduleConfig:rabbitsdk";
	property name="interceptorService" inject="box:InterceptorService";
//	property name="javaloader" inject="loader@cbjavaloader";
	property name="log" inject="logbox:logger:{this}";
	property name="rabbitJavaLoader" inject="rabbitJavaLoader@RabbitSDK";
	property name="RPCClients" type="struct";
	

	/** The RabbitMQ Connection */
	property name="connection" type="any";
	property name="clientID" type="string";
	
	/**
	 * Constructor
	 */
	function init(){
		setClientID( createUUID() );
		setRPCClients( {} );
		return this;
	}
	
	function onDIComplete(){
		log.debug( 'Rabbit client intialized. ClientID: #getClientID()#' );
		interceptorService.registerInterceptor( 
			interceptor 	= this, 
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
	function connect( string host, string port, string username, string password, string virtualHost, boolean useSSL, boolean quiet=false, string sslProtocol = 'TLSV1.2' ){
		
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
			var factory = rabbitJavaLoader.create( "com.rabbitmq.client.ConnectionFactory" ).init();
			factory.setHost( thisHost );
			factory.setUsername( thisUsername );
			factory.setPassword( thisPassword );
			
			if( isBoolean( thisUseSSL ) ) {
				factory.useSslProtocol( arguments.sslProtocol );	
			}
			
			if( len( thisVirtualHost ) ) {
				factory.setVirtualHost( thisVirtualHost );	
			}
			
			factory.setRequestedHeartbeat( 20 );
			if( val( thisPort ) != 0 ) {
				factory.setPort( thisPort );	
			}			
			
			factory.setConnectionTimeout( 5000 );
			
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
	 * Creates an auto-closing channel for multiple operations.  Do not store the channel reference passed to the callback
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
	 * Listen to the CommandBox CLI shutting down
	 */
	function onCLIExit() {
		log.debug( 'CLI shutdown detected.' );
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
				
				// Shut down any RPCCLients.
				getRPCCLients().each( ( k, v )=>v.$close() );
				
				getConnection().close();
				structDelete( variables, 'connection' );
			}
			interceptorService.unregister( "rabbitsdk-client-#getClientID()#" );
		}
	}

	/**
	 * Return true if client has connection to RabbitMQ Server.
	 */
	boolean function hasConnection() {
		return !isNull( variables.connection );
	}

	/**
	 * Return an RPC Client for a given exchange/routing key/timeout, creating it if neccessary
	 *
	 * @exchange Name of exchange to send RPC messages to
	 * @routingKey Name of routing key to send RPC messages to
	 * @timeout Timeout in seconds to wait for reply.  0 to wait forever (not recomended)
	 */
	function RPCClient(
		string routingKey='RPC_Queue',
		numeric timeout=15,
		string exchange=''
	) {
		var RPCClientHash = hash( 'exchange:#exchange#:routingKey:#routingKey#:timeout:#timeout#' );
		var lockName = 'rabbitMQ-#getClientID()#-RPCCLient';
		var clients = getRPCClients();
		lock name="#lockName#" type="readonly" timeout="30" {
			if( clients.keyExists( RPCClientHash ) ) {
				return clients[ RPCClientHash ];
			}
		}
		lock name="#lockName#" type="exclusive" timeout="30" {
			if( clients.keyExists( RPCClientHash ) ) {
				return clients[ RPCClientHash ];
			}
			var newClient = wirebox.getInstance( 'RPCClient@rabbitsdk' )
				.$configure(
					RPCClientHash,
					this,
					arguments.exchange,
					arguments.routingKey,
					arguments.timeout
				);
			clients[ RPCClientHash ] = newClient;
			return newClient;
		}
		
	}
	
	/**
	* Start consumer thread which will listen for messages and reply back.  
	* If you pass a UDF to the "consumer" argument, it will be invoked for every message and will receive 
	* a "message" and "arg" paramter.  The return value of the UDF will be sent back to the RPC client.
	* If you pass a CFC instance to the "consumer" argument, a public method whose name matches the incoming
	* RPC "method" will be called and the "args" will be passed via argumentCollection. The return value of the CFC's 
	* method will be sent back to the RPC client.
	* 
	* @queue Name of the queue to watch for incoming RPC message
	* @consumer A UDF or CFC instance to be called for each message.
	*/
	function startRPCServer(
		required string queue,
		any consumer
	) {
		queueDeclare( queue );
		var nullMe=()=>{}
		return startConsumer( 
			queue=queue,
			consumer=(message,channel,log)=>{
				var rpc = message.getBody();
				var results = '';
				var isError = false;
				try {
					if( isObject( consumer ) ) {
						results = invoke( consumer, rpc.method, rpc.args );
					} else {
						results = consumer( rpc.method, rpc.args );	
					}
				} catch( any e ) {
					isError = true;
					results = e;
				} finally {
					channel.publish(
						{
							'result' : ( isNull( results ) ? nullMe() : results),
							'isError' : isError
							
						},
						message.getReplyTo(),
						'',
						{
							'correlationId' : message.getCorrelationId() 
						}
					)	
				}
			}
		);
	}

	/**
	 * Remove an RPC Client
	 *
	 * @RPCCLientHash Hash of the RPC client to remove
	 */
	function removeRPCClient(
		required string RPCClientHash
	) {
		var lockName = 'rabbitMQ-#getClientID()#-RPCCLient';
		var clients = getRPCClients();
		
		if( !clients.keyExists( RPCClientHash ) ) {
			return;
		}
		
		lock name="#lockName#" type="exclusive" timeout="30" {
			if( !clients.keyExists( RPCClientHash ) ) {
				return;
			}
			
			clients.delete( RPCClientHash );
		}
	}
	
	
	// CONVEIENCE METHODS THAT AUTOMATICALLY HANDLE YOUR CHANNEL FOR YOU
	
	
	
	/**
	* @name the name of the exchange
	* @type Type of exchange.  Valid values are direct, fanout, headers, and topic
	* @durable true if we are declaring a durable exchange (the exchange will survive a server restart)
	* @autoDelete true if the server should delete the exchange when it is no longer in use
	* @internal true if the exchange is internal, i.e. can't be directly published to by a client.
	* @queueArguments  Struct of other properties (construction arguments) for the exchange
	* 
	* Declare a new exchange.
	*/
	function exchangeDeclare(
		required string name,
		string type='direct',
		boolean durable=true,
		boolean autoDelete=false,
		boolean internal=false,
		struct exchangeArguments={}
	) {
		var args = arguments;
		batch( (channel)=>channel.exchangeDeclare( argumentCollection=args ) );
		return this;
	}

	/**
	* @name the name of the exchange
	* @ifUnused true to indicate that the exchange is only to be deleted if it is unused
	* 
	* delete an exchange.
	*/
	function exchangeDelete(
		required string name,
		boolean ifUnused=false
	) {	
		var args = arguments;
		batch( (channel)=>channel.exchangeDelete( argumentCollection=args ) );
		return this;
	}

	/**
	* @destination The name of the exchange to which messages flow across the binding
	* @source The name of the exchange from which messages flow across the binding
	* @routingKey The routing key to use for the binding
	* @bindArguments A struct of other properties (binding parameters)
	* 
	* Bind an exchange to an exchange.
	*/
	function exchangeBind(
		required string destination,
		required string source,
		required string routingKey,
		struct bindArguments={}
	) {	
		var args = arguments;
		batch( (channel)=>channel.exchangeBind( argumentCollection=args ) );
		return this;
	}

	/**
	* @destination The name of the exchange to which messages flow across the binding
	* @source The name of the exchange from which messages flow across the binding
	* @routingKey The routing key to use for the binding
	* @bindArguments A struct of other properties (binding parameters)
	* 
	* Unbind an exchange from an exchange.
	*/
	function exchangeUnbind(
		required string destination,
		required string source,
		required string routingKey,
		struct bindArguments={}
	) {	
		var args = arguments;
		batch( (channel)=>channel.exchangeUnbind( argumentCollection=args ) );
		return this;
	}
	
	/**
	* @name the name of the exchange
	* 
	* Returns true if exchange exists, false if it doesn't.  Be careful calling this method under load as it 
	* catches a thrown exception if the exchange doesn't exist so it probably doesn't perform great if the exchange you
	* are checking doesn't exist most of the time.
	*/
	boolean function exchangeExists( required string name ) {
		var args = arguments;
		return batch( (channel)=>channel.exchangeExists( argumentCollection=args ) );
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
		boolean durable=true,
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
	* @exchange the name of the exchange
	* @routingKey the routing key to use for the binding
	* @bindArguments Struct of other properties (binding parameters)
	* 
	* Unbind a queue from an exchange.
	*/
	function queueUnbind(
		required string queue,
		required string exchange,
		required string routingKey,
		struct bindArguments={}
	) {
		var args = arguments;
		batch( (channel)=>channel.queueUnbind( argumentCollection=args ) );
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
	* @consumer A UDF or CFC method name (when component is specified) to be called for each message. 
	* @error A UDF or CFC method name (when component is specified) to be called in case of an error in the consumer
	* @component Name or instance of component containing "onMessage" and/or "onError" methods.  Don't use if passing closures for "consumer" and "error"
	* @autoAcknowledge Automatically ackowledge each message as processed
	* @prefetch Number of messages this consumer should fetch at once. 0 for unlimited
	*/
	function startConsumer(
		required string queue,
		any consumer='onMessage',
		any error='onError',
		any component,
		boolean autoAcknowledge=true,
		numeric prefetch=1
	) {
		var args = arguments;
		return createChannel().startConsumer( argumentCollection=args );
	}
	
}