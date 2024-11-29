/**
 * Utility component to help loading java classes from
 * RabbitMQ library
 *
 */
component singleton ThreadSafe {

	property name="wirebox" inject="wirebox";

	public any function init() {
		if ( isLucee() ) {
			var libDir = ExpandPath( getDirectoryFromPath( getCurrentTemplatePath() ) & "../lib" );
			variables.jars = DirectoryList( libDir, true, "path", "*.jar" );
		}
	}

	public any function create( required string className ) {
		if ( isLucee() ) {
			return CreateObject( "java", arguments.className, variables.jars );
		} else {
			// TODO: use javaloader with ACF?
			return CreateObject( "java", arguments.className );
		}
	}

	public any function getConsumerProxy() {
		var consumerInstance = wirebox.getInstance( name='consumer@rabbitsdk', initArguments=arguments );
		if ( isLucee() ) {
			return createDynamicProxy( consumerInstance, [ create( "com.rabbitmq.client.Consumer" ) ] );
		} else {
			// TODO: use javaloader with ACF?
			return createDynamicProxy( consumerInstance, [ "com.rabbitmq.client.Consumer" ] );
		}
	}

	private boolean function isLucee() {
		return StructKeyExists( server, "lucee" );
	}

}