component{

	// Configure ColdBox Application
	function configure(){

		// coldbox directives
		coldbox = {
			//Application Setup
			appName 				= "Module Tester",

			//Development Settings
			reinitPassword			= "",
			handlersIndexAutoReload = true,
			modulesExternalLocation = [],

			//Implicit Events
			defaultEvent			= "",
			requestStartHandler		= "",
			requestEndHandler		= "",
			applicationStartHandler = "",
			applicationEndHandler	= "",
			sessionStartHandler 	= "",
			sessionEndHandler		= "",
			missingTemplateHandler	= "",

			//Error/Exception Handling
			exceptionHandler		= "",
			onInvalidEvent			= "",

			//Application Aspects
			handlerCaching 			= false,
			eventCaching			= false
		};

		// environment settings, create a detectEnvironment() method to detect it yourself.
		// create a function with the name of the environment so it can be executed if that environment is detected
		// the value of the environment is a list of regex patterns to match the cgi.http_host.
		environments = {
			development = "localhost,127\.0\.0\.1"
		};

		// Module Directives
		modules = {
			// An array of modules names to load, empty means all of them
			include = [],
			// An array of modules names to NOT load, empty means none
			exclude = []
		};

		//Register interceptors as an array, we need order
		interceptors = [
		];

		//LogBox DSL
		logBox = {
			// Define Appenders
			appenders = {
				ConsoleAppender = {
					class="coldbox.system.logging.appenders.ConsoleAppender"
				}
			},
			// Root Logger
			root = { levelmax="DEBUG", appenders="*" },
			// Implicit Level Categories
			info = [ "coldbox.system" ]
		};

		moduleSettings = {
			rabbitsdk = {
				host : getSystemSetting( 'rabbit_host', 'localhost' ),
				username : getSystemSetting( 'rabbit_username', 'guest' ),
				password : getSystemSetting( 'rabbit_password', 'guest' ),
				virtualHost : getSystemSetting( 'rabbit_virtualHost', '/' ),
				useSSL : getSystemSetting( 'rabbit_useSSL', '' )
			}
		};

	}

	/**
	 * Load the Module you are testing
	 */
	function afterAspectsLoad( event, interceptData, rc, prc ){
		controller.getModuleService()
			.registerAndActivateModule(
				moduleName 		= request.MODULE_NAME,
				invocationPath 	= "moduleroot"
			);
	}

}