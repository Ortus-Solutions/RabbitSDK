/**
*********************************************************************************
* Copyright Since 2005 ColdBox Framework by Luis Majano and Ortus Solutions, Corp
* www.ortussolutions.com
* ---
* Module Config.
*/
component {

	// Module Properties
	this.title 				= 'RabbitSDK';
	this.author 			= 'Brad Wood';
	this.version 			= '@build.version@+@build.number@';
	this.cfmapping			= 'rabbitsdk';
//	this.dependencies		= [ 'cbjavaloader' ];

	function configure(){
		settings = {
			host : 'localhost',
			username : 'guest',
			password : 'guest',
			port : 5672
		};
		
	}

	function onLoad(){
	/*	var javaloader = controller.getWireBox().getInstance( "loader@cbjavaloader" );
		controller.getConfigSettings().modules.cbjavaloader.settings.loadColdFusionClassPath = true;
		javaloader.setup();
		
		javaloader.appendPaths( expandPath( '/rabbitsdk/lib' ) );*/
	}

	function onUnload(){
	}

}
