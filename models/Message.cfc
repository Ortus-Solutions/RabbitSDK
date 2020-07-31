/**
* This is a transient that represents a single message
*/
component accessors='true'  {

	/** The RabbitMQ Connection this channel belongs to */
	property name='connection' type='any';
	/** The RabbitMQ Channel object */
	property name='channel' type='any';
		
	property name='rawEnvelope' type='any';
	property name='acknowledged' type='boolean' default='false';
	property name='rejected' type='boolean' default='false';
	property name='rawProperties' type='any';
	property name='rawBody' type='any';
	
	property name='body' type='any';
	
	// Envelope
	property name='deliveryTag' type='any';
	property name='exchange' type='any';
	property name='routingKey' type='any';
	property name='isRedeliver' type='any';
	
	// Properties
	property name='appId' type='string';
	property name='clusterId' type='string';
	property name='contentEncoding' type='string';
	property name='contentType' type='string';
	property name='correlationId' type='string';
	property name='deliveryMode' type='string';
	property name='expiration' type='string';
	property name='headers' type='struct';
	property name='messageId' type='string';				
	property name='priority' type='string';
	property name='replyTo' type='string';
	property name='timestamp' type='string';
	property name='type' type='string';
	property name='userId' type='string';
	
	function populate( required any envelope, required any properties, required any body ) {
			
		setRawEnvelope( envelope );
		setRawProperties( properties );
		setRawBody( body );
		setBody( toString( body ) );
		
		setDeliveryTag( envelope.getDeliveryTag() );
		setExchange( envelope.getExchange() );
		setRoutingKey( envelope.getRoutingKey() );
		setIsRedeliver( envelope.isRedeliver() );
		
		setAppId( properties.getAppId() ?: '' );
		setClusterId( properties.getClusterId() ?: '' );
		setContentEncoding( properties.getContentEncoding() ?: '' );
		setContentType( properties.getContentType() ?: '' );
		setCorrelationId( properties.getCorrelationId() ?: '' );
		// TODO: Translate from number to string
		setDeliveryMode( properties.getDeliveryMode() ?: '' );
		setExpiration( properties.getExpiration() ?: '' );
		setHeaders( properties.getHeaders() ?: {} );
		setMessageId( properties.getMessageId() ?: '' );		
		setPriority( properties.getPriority() ?: '' );
		setReplyTo( properties.getReplyTo() ?: '' );
		setTimestamp( properties.getTimestamp() ?: '' );
		setType( properties.getType() ?: '' );
		setUserId( properties.getUserId() ?: '' );
		
		// Force this to be a native CFML Struct instead of Map<String,Object>
		var emptyStruct = {};
		setHeaders( emptyStruct.append( getHeaders().map( (k,v)=>v.toString() ) ) );
		
		// If we got a complex object in, send it out the same way
		if( getHeader( '_autoJSON', false ) ) {
			setBody( deserializeJSON( getBody() ) );
		}
		
		return this;
	}
	
	/**
	* @name Name of header
	* @defaultValue Default value to use if it doesn't exist or is null
	* 
	* Get a specific header from the message.
	*/
	function getHeader( required string name, any defaultValue ){
		var headers = getHeaders();
		if( !headers.keyExists( name ) ) {
			if( isNull( defaultvalue ) ) {
				return;
			} else {
				return defaultValue;
			}
		}
		return headers[ name ];
	}
	
	/**
	* Acknowledge this message as processed.  Only neccessary if autoAck is off
	*/
	function acknowledge(){
		if( isCommitted() ) {
			return this;
		}
		setAcknowledged( true );
		getChannel().basicAck( getDeliveryTag(), false );
		return this;
	}
	
	/**
	* @requeue True to put message back in queue, false to discard message
	*
	* Reject this message as processed.  Only neccessary if autoAck is off
	*/
	function reject( boolean requeue=false ){
		if( isCommitted() ) {
			return this;
		}
		setRejected( true );
		getChannel().basicReject( getDeliveryTag(), requeue );
		return this;
	}
	
	/**
	* Has this message been previously acknowledged?
	*/
	boolean function isAcknowledged() {
		return getAcknowledged() == true;
	}
	
	/**
	* Has this message been previously rejected?
	*/
	boolean function isRejected() {
		return getRejected() == true;
	}
	
	/**
	* Has this message been previously acknowledged or rejected?
	*/	
	boolean function isCommitted() {
		return isAcknowledged() || isRejected();
	}
	
}