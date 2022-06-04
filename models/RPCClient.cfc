/**
* This is a transient that represents an RPC Client.  This should be reused on repeated calls so the same
* temp queue and consumer thread can be re-used.  It is safe to share this between threads, and even though it's a 
* "transient", you should keep it around so long as you intend to continue making RPC calls to the same remote
* exchange and routing key.  Close this client if you aren't going to use it again, to free up resources.
*
* Accessors are disabled so onMissingMethod will always fire on our proxy
*/
component accessors="false"  {

	// DI
	property name="log" inject="logbox:logger:{this}";
		
	property name="RabbitClient" type="any";
	/** The RabbitMQ Channel object */
	property name="channel" type="any";
	property name="jRPCClient" type="any";
	property name="exchange" type="string" default="";
	property name="routingKey" type="string" default="RPC_Queue";
	property name="timeout" type="numeric" default="15";
	property name="RPCClientHash" type="string";
	
	/**
	 * configure a new Client
	 * 
	 * @RPCClientHash Unique hash of this cient for later removal
	 * @rabbitClient The associated RabbitClient
	 * @exchange Name of exchange to send RPC messages to
	 * @routingKey Name of routing key to send RPC messages to
	 * @timeout Timeout in seconds to wait for reply.  0 to wait forever (not recomended)
	*/
	function $configure(
		string RPCClientHash=variables.RPCClientHash,
		any rabbitClient=variables.rabbitClient,
		string exchange=variables.exchange,
		string routingKey=variables.routingKey,
		numeric timeout=variables.timeout
		
	) {
		variables.RPCClientHash = arguments.RPCClientHash;
		variables.rabbitClient = arguments.RabbitClient;
		variables.exchange = arguments.exchange;
		variables.timeout = arguments.timeout;
		variables.routingKey = arguments.routingKey;
		variables.channel = rabbitClient.createChannel();
		
		// Create a new instance of the java RPC Client class using a RPCClientParams instance to configure it.
		variables.jRPCCLient = createObject( 'java', 'com.rabbitmq.client.RpcClient' ).init(
			createObject( 'java', 'com.rabbitmq.client.RpcClientParams' )
				.channel( channel.getChannel() )
				.exchange( arguments.exchange )
				.routingKey( arguments.routingKey )
				.timeout( arguments.timeout )	
		);
		log.debug( 'Rabbit RPC Client intialized with exchange: [#exchange#] routingKey: [#routingKey#]' );
		return this;
	}
		
	/**
	 * Sent an RPC call and wait for the reponse until the given timeout.  If no timeout is provided, the default one is used that was 
	 * passed when creating the client.
	 *
	 * @method Name of RPC method to invoke
	 * @args Struct or array of arguents to pass to remote method
	 * @timeout Timeout in seconds to wait for reply.  0 to wait forever (not recomended)
	*/
	function $call(
		required string method,
		any args={},
		numeric timeout=variables.timeout
	) {		
		// If this channel has been closed, create a new one
		if( !channel.getChannel().isOpen() ){
			log.debug( 'RPC Channel is closed, reconfiguring RPC client.' );
			$configure();
		}

		var propBuilder = channel.getMessagePropertiesBuilder().init();
		propBuilder.correlationId( createUUID() );
		propBuilder.headers( {
			'_autoJSON' : 'true'
		} );
		
		var body = serializeJSON( {
			'method' : arguments.method,
			'args' : args
		} );
		
		try {
			try {
				var response = jRPCClient.doCall(
					propBuilder.build(),
					body.getBytes(),
					arguments.timeout*1000
				);
			} catch( any e ) {
				// If the RPCClient's consumer has stopped, close the channel and re-create the ciient
				if( e.message contains 'RpcClient is closed' ) {
					log.debug( 'RPC Client is closed, reconfiguring RPC client.  ' );
					channel.close();
					$configure();
					
					// Try again with the fresh RPC Client
					var response = jRPCClient.doCall(
						propBuilder.build(),
						body.getBytes(),
						arguments.timeout*1000
					);
					
				} else {
					rethrow;
				}
			}
			var headers = response.getProperties().getHeaders() ?: {};
			// Force this to be a native CFML Struct instead of Map<String,Object>
			var emptyStruct = {};
			headers = emptyStruct.append( headers.map( (k,v)=>v.toString() ) );
			var body = toString( response.getBody() );
			// If we got a complex object in, send it out the same way
			if( headers._autoJSON ?: false ) {
				body = deserializeJSON( body );
			}
			
			if( body.isError ) {
				var ex = body.result;
				ex.message &= ' ' & ex.detail;
				ex.detail = ex.stackTrace;
				throw( message=ex.message, detail=ex.detail, type=ex.type, extendedInfo=ex.extendedInfo, errorCode=ex.errorCode );
			}
			
			// Allow null to be returned from RPC call
			if( isNull( body.result ) ) {
				return;
			}
			return body.result;
			
		} catch( any e ) {
			if( e.type contains 'TimeoutException' ) {
				throw( message='RPC Call to [#method#] timed out after #arguments.timeout# second#arguments.timeout == 1 ? '' : 's'#', type=e.type );
			} else if( e.type contains 'ShutdownSignalException' ) {
				throw( message='RPC Call to [#method#] aborted due to a cilent shutdown that is in progress.', type=e.type );
			} else if( e.message contains 'RpcClient is closed' ) {
				throw( message='RPC Client cannot connect to RabbitMQ at this time.', type=e.type );
			}
			rethrow;
		}
	}
		
	/**
	* A proxy for directly invoking remote methods
	*/
	function onMissingMethod( missingMethodName, missingMethodArguments ) {
		return $call( missingMethodName, missingMethodArguments );
	}
		
	/**
	* Call this method when you are finished using it to free resources
	*/
	function $close() {
		rabbitClient.removeRPCClient( RPCClientHash )
		jRPCClient.close();
		log.debug( 'Rabbit RPC Client shutdown with exchange: [#exchange#] routingKey: [#routingKey#]' );
		return this;
	}

}