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
	function connect( string host, string port, string username, string password, boolean quiet=false ){
		
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
			
			if( !thisHost.len() && !thisUsername.len() ) {
				throw( 'No Rabbit Host and username configured.  Cannot connect.' );
			}
			
			log.debug( 'Creating connection to [#thisHost#]' );
			
			//var factory = javaloader.create( "com.rabbitmq.client.ConnectionFactory" ).init();
			var factory = createObject( "java", "com.rabbitmq.client.ConnectionFactory" ).init();
			factory.setHost( thisHost );
			factory.setUsername( thisUsername );
			factory.setPassword( thisPassword );
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
	 * Creates an auto-closing channel for a single operation.  Do not store the channel refernce passed to the callback
	 * as it will be closed as soon as the UDF is finished.  Any value returned from the UDF will be returned from the
	 * channelDo method.  This is preferred for one-off operations so you don't need to worry about closing the channel.
	 * If you have a large number of operations to perform on the channel, it is best to re-use the same channel and 
	 * simply remember to close it when you're finished.
	 */
	function channelDo( required any udf ) {
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

}
