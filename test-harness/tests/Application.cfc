/**
********************************************************************************
Copyright 2005-2007 ColdBox Framework by Luis Majano and Ortus Solutions, Corp
www.ortussolutions.com
********************************************************************************
*/
component{

	// APPLICATION CFC PROPERTIES
	this.name 				= "ColdBoxTestingSuite" & hash(getCurrentTemplatePath());
	this.sessionManagement 	= true;
	this.sessionTimeout 	= createTimeSpan( 0, 0, 15, 0 );
	this.applicationTimeout = createTimeSpan( 0, 0, 15, 0 );
	this.setClientCookies 	= true;

	// Create testing mapping
	this.mappings[ "/tests" ] = getDirectoryFromPath( getCurrentTemplatePath() );
	
	// The application root
	rootPath = REReplaceNoCase( this.mappings[ "/tests" ], "tests(\\|/)", "" );
	this.mappings[ "/root" ]   = rootPath;
	this.mappings[ "/testbox" ] = rootPath & "/testbox";
	this.mappings[ "/coldbox" ] = rootPath & "/coldbox";

	// UPDATE THE NAME OF THE MODULE IN TESTING BELOW
	request.MODULE_NAME = "RabbitSDK";

	// The module root path
	moduleRootPath = REReplaceNoCase( this.mappings[ "/root" ], "#request.module_name#(\\|/)test-harness(\\|/)", "" );
	this.mappings[ "/moduleroot" ] = moduleRootPath;
	this.mappings[ "/#request.MODULE_NAME#" ] = moduleRootPath & "#request.MODULE_NAME#";

	this.javaSettings = {
		loadPaths = directorylist( expandPath( moduleRootPath & '#request.MODULE_NAME#/lib' ), true, 'array', '*jar' ),
		loadColdFusionClassPath = true,
		reloadOnChange = false
	};

	function onRequestEnd() {
		structClear( application );
	}

}