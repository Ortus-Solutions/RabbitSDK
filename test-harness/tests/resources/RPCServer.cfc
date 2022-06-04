component {
	
	function echo(){
		return arguments;
	}
	
	function null(){
		return;
	}
	
	function error(){
		throw( message="error message", detail="error detail", type="RPC_BLEW_CHUNKS" );
	}
	
	function myMethod(){
		return 'You called [myMethod]';
	}
	
}