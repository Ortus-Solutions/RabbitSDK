component {
	
	function onMessage( message, channel, log ) {
		log.info( 'My Consumer received message #message.getBody()#' );
	}
	
	function onError( message, channel, log, exception ) {
		log.error( 'Error processing message #message.getBody()#.  Error message: #exception.message#' );
		// Phone home to the test suite that we ran
		application.consumerOnErrorFired=true;
	}
	
}