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
		// Stupid Lucee bug 
		// https://luceeserver.atlassian.net/browse/LDEV-2296
		// This class represents the Rabbit Consumer instance which implements the Rabbit Consumer interface
		// If not cleared on every server resetart, Lucee will stop recognizing that the class implements the proper interface
		// and java reflection calls to channel.basicConsume() will start failing.
		
		var luceeRPCProxyClassFile = expandPath('/lucee/../cfclasses/RPC/Vdc65763751ec3c6ac73173d2c2e627944384.class');
		if( server.keyExists( 'lucee' ) && fileExists( luceeRPCProxyClassFile ) ) {
			fileDelete( luceeRPCProxyClassFile );
		}
		
	/*	var javaloader = controller.getWireBox().getInstance( "loader@cbjavaloader" );
		controller.getConfigSettings().modules.cbjavaloader.settings.loadColdFusionClassPath = true;
		javaloader.setup();
		
		javaloader.appendPaths( expandPath( '/rabbitsdk/lib' ) );*/
	}

	function onUnload(){
	}

}
