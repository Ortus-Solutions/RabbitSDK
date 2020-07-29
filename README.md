[![CI](https://github.com/Ortus-Solutions/RabbitSDK/workflows/CI/badge.svg)](https://github.com/Ortus-Solutions/RabbitSDK/actions)




# Welcome to the RabbitMQSDK Module

RabbitMQ is an open-source message-broker software that originally implemented the Advanced Message Queuing Protocol and has since been extended with a plug-in architecture to support Streaming Text Oriented Messaging Protocol, MQ Telemetry Transport, and other protocols.

This library is a wrapper for CFML/ColdFusion apps to be able to interact with RabbitMQ via the Java SDK.  

## LICENSE

Apache License, Version 2.0.

## IMPORTANT LINKS

- Source: https://github.com/Ortus-Solutions/RabbitSDK
- Issues: https://ortussolutions.atlassian.net/browse/BOX

## SYSTEM REQUIREMENTS

- Lucee 5
- Adobe 2018

Previous Adobe versions may work, I just haven't tested them yet.

## Installation

Install into your modules folder using the `box` cli to install

```bash
box install rabbitsdk
```

Due to a nasty classloading issue with Lucee, I had to abandon using Javaloader:
https://luceeserver.atlassian.net/browse/LDEV-2296

As such, it is required for you to be responsible for loading the Rabbit jar into your application.
If this is a CFML web app, you can add this to your `Application.cfc`

```js
	this.javaSettings = {
		loadPaths = directorylist( expandPath( '/modules/rabbitsdk/lib' ), true, 'array', '*jar' ),
		loadColdFusionClassPath = true,
		reloadOnChange = false
	};
```

Or if you are using this module from the CLI, you can load the jars in a task runner or custom command in CommandBox prior to using the module like so:
```js
classLoad( 'expandPath( '/rabbitsdk/lib' )' );
```

# Usage

This module wraps and _simplifies_ the java SDK.  There are only a few CFCs for you to worry about, and while not 100% of the Java SDK functionality is exposed, all the major functions are here.

* Manage queues
* Send messages
* Consume messages

Here are the major CFCs you need to know about:

* **RabbitClient** - Singleton that represents a single connection to the Rabbit server. 
* **Channel** - Transient for all interactions with Rabbit.
* **Message** - Transient that represents a message received from the server.


## RabbitClient

Create this only once and re-use over the life of your app.  The CFC is marked as a singleton, so if you are using WireBox to access it, you don't need to manually cache it anywhere.
Simply inject it wherever you need and use it.  It is very important to call the `shutdown()` method to release the connection when your app is shutting down or reiniting.

```js
wirebox.getInstance( 'RabbitClient@rabbitsdk' );
```
or 

```js
property name='rabbitClient' inject='RabbitClient@rabbitsdk';
```

Each `RabbitClient` instance contains a single connection which is auto-created on first use if you have supplied the connection details in the module settings in `/config/Coldbox.cfc`.

```js
moduleSettings = {
	// here we are pulling from environment variables, by
	// but these can also just be hard-coded in
	rabbitsdk = {
		host : getSystemSetting( 'rabbit_host' ),
		username : getSystemSetting( 'rabbit_username' ),
		password : getSystemSetting( 'rabbit_password' ),
		virtualHost : getSystemSetting( 'rabbit_virtualHost' ),
		useSSL : getSystemSetting( 'rabbit_useSSL' )
	}
};
```

You can also manually create your connection, which only needs to happen once:

```js
rabbitClient.connect( host='localhost', port=5672, username='guest', password='guest', virtualHost='/', useSSL=true );
```   

In ColdBox, the RabbitClient will register a `prereinit` interceptor listener to shut itself down when the framework reinits.  If you have another scenario such as a test case suite that simply clears the application scope 
when it's finished, it will leave hanging connections which you can see in the web-based management UI.

If you want to have more than one connection, then create additional WireBox mappings for this CFC and create them individually.  

```js
// In your /config/Wirebox.cfc
map( 'PublishClient' ).to( 'rabbitsdk.models.RabbitClient' );
map( 'ConsumerClient' ).to( 'rabbitsdk.models.RabbitClient' );

// In your application
wirebox.getInstance( 'ConsumerClient' )
	.startConsumer( 
		queue='myQueue',
		consumer=(message, channel, log)=>{
			log.info( 'Message received: #message.getBody()#' );
		} );
		
wirebox.getInstance( 'PublishClient' )
	.publish( 'My message', 'myQueue' )
	.publish( 'Another message', 'myQueue' )
	.publish( 'Still more messages', 'myQueue' );
	

```

Interactions with Rabbit actually happen over a channel, but the rabbitClient has a convenience method for all operations that automatically create and close the channel for you.

All methods that don't return some explicit value return `this` so you can do method chaining like so:

```js
rabbitClient
	.queueDeclare( 'myQueue' )
	.queuePurge( 'myQueue' )
	.publish( 'My message', 'myQueue' );
```  

If you have a large number of operations and you want to perform them on the same channel then the best approach is to use the `batch()` method in the client CFC.  It's less network traffic to re-use the same channel
so sending 1,000 messages is something you'd want to do over a single channel for the best performance. 

```js
rabbitClient.batch( (channel)=> {
	channel
		.queueDeclare( 'myQueue' )
		.queuePurge( 'myQueue' )
		// This could easily be a dynamic loop over a query, etc
		.publish( 'Message 1', 'myQueue' )
		.publish( 'Message 2', 'myQueue' )
		.publish( 'Message 3', 'myQueue' )
		.publish( 'Message 4', 'myQueue' ); 
});
```

The `batch()` method accepts a closure and
* Creates the channel for you
* Passes it to your UDF for usage
* Auto-closes it when done in an internal finally block

### Send a Message

You can minimally publish a message with the routing key and message text.

```js
rabbitClient.publish( 'My message', 'myQueue' );
```

You can publish complex data like structs or arrays and the message will be automatically JSON serialized for you and deserialized when you read the message back.

```js
var data = {
	name:'brad',
	age:40,
	hair:'red',
	likes:[
		'music',
		'computers',
		'procrastinating'
	]
};
rabbitClient.publish( data, 'myQueue' );
```

Rabbit also allows you to send additional properties for a message.  Most properties are a string value, but headers are a struct of name/value pairs.  You can see a full list
of supported properties below in the `Message` section.

```js
rabbitClient.publish( 
			body='My Message',
			routingKey='myQueue',
			props={
				'contentEncoding':'UTF-8',
				'contentType':'text/plain',
				'deliveryMode':1,
				'headers':{
					'header 1' :'value 1',
					'header 2' :'value 2',
					'header 3' :'value 3'
				},
				'priority':5
			}
		);
```

### Get a single message

You can consume a single message at a time like so.  See the `Message` section below.  

```js
var message = rabbitClient.getMessage( 'myQueue' );
```

### Start a consumer

The recommended way to process messages is to start a consumer.  Each channel can have a single consumer started.  A consumer only needs to be started once.  
The consumer will run until it is stopped, the channel is closed, or the client is shutdown.
A consumer runs in a separate thread so starting the consumer is a non-blocking operation.  You pass a UDF/closure or a CFC instance to the consumer which will be called once for every message that comes in.  

Arguments:

* **queue** - Name of the queue to consume
* **consumer** - A UDF or CFC method name (when component is specified) to be called for each message. 
* **error** - A UDF or CFC method name (when component is specified) to be called in case of an error in the consumer
* **component** - Name or instance of component containing "onMessage" and/or "onError" methods.  Don't use if passing closures for "consumer" and "error"
* **autoAcknowledge** - Automatically ackowledge each message as processed
* **prefetch** - Number of messages this consumer should fetch at once. 0 for unlimited

Here is an example of using ad-hoc closures to handle messages and errors:
```js
var channel = rabbitClient
		.startConsumer( 
			queue='myQueue',
			autoAcknowledge=false,
			consumer=(message, channel, log)=>{
				log.info( 'Consumer 1 Message received: #message.getBody()#' );
				message.acknowledge();
			},
			error=(message, channel, log, exception)=>{
				log.error( 'Error processing message #message.getBody()#.  Error message: #exception.message#' );
			} );
			
```

And here is an example of specying a component.  Note, the `consumer` and `error` parameters default to `onMessage` and `onError`.  They are provided here just for clarity, but could be omitted if not changed from the default.  Also, `component` can be either the instance or a CFC path or a WireBox mapping.  `wirebox.getInstance()` is used to create it.

```js
var channel = getRabbitClient()
		.startConsumer( 
			queue='myQueue',
			autoAcknowledge=false,
			component='MyConsumer,
			consumer='onMessage',
			error='onError'
		);

// MyConsumer.cfc
component {
	
	function onMessage( message, channel, log ) {
		log.info( 'My Consumer received message #message.getBody()#' );
		message.acknowledge();
	}
	
	function onError( message, channel, log, exception ) {
		log.error( 'Error processing message #message.getBody()#.  Error message: #exception.message#' );
	}
	
}
```

The `consumer` callback method (whether a closure or in a CFC) receives three arguments:

* **message** - An instance of the `Message` CFC outlined below
* **channel** - The RabbitSDK Channel instance. You can use this channel to query the queue, send additional messages, etc.
* **log** - An instance of the LogBox logger from the consumer class, useful for debugging.

The `error` callback method (whether a closure or in a CFC) receives four arguments:

* **message** - An instance of the `Message` CFC outlined below
* **channel** - The RabbitSDK Channel instance. You can use this channel to query the queue, send additional messages, etc.
* **log** - An instance of the LogBox logger from the consumer class, useful for debugging.
* **exception** = The excepton object that was thrown from the `consumer` method.

The `startConsume()` method returns a `Channel` instance which you can use to stop the consumer later.   When you start more than one consumer, a new channel is created for each one.  
Save the channel refernce so you can stop the consumer later.  Closing the channel will also stop the consumer.

```js
var channel1 = rabbitClient.startConsumer( 'myQueue', ()=>{} );
var channel2 = rabbitClient.startConsumer( 'myQueue', ()=>{} );
var channel3 = rabbitClient.startConsumer( 'myQueue', ()=>{} );


// Later on, after you're done processing messages:
channel1.close()
channel2.close()
channel3.close()
```

When you have more than one consumer, they will compete for messages and work them in parallel.  By default, a consumer will only pull one message at a time to work.  This is ideal for several consumers completing
tasks that take a while to process and you want to evenly distribute load among the consumers.  If you have a very large number of messages and processing time is very fast, you can improve performance by increasing your
prefetch amount so a consumer grabs more than one message to work at a time reduces network traffic between messages.

```js
rabbitClient.startConsumer( name='myQueue', consumer=()=>{}, prefetch=10 );
```

The consumer above will fetch up to 10 messages at a time to process (if that many are available in the queue)

## Message

Transient that represents a message received from the server for you to process.  Each message instance has the following getters you can call:

* **getBody()** - The body of the message. Usually a string, but if you passed an array or struct when sending the message, it will be automatically deserialized for you
* **getDeliveryTag()** - Delivery tag of message
* **getExchange()** - Name of exchange that processed the message
* **getRoutingKey()** - Name of routing key for message
* **getIsRedeliver()** - isRediliver flag (boolean)
* **getAppId()** - App ID
* **getClusterId()** - Cluster ID
* **getContentEncoding()** - Content encoding of message
* **getContentType()** -  Content type of message
* **getCorrelationId()** - Correlation ID
* **getDeliveryMode()** - Delivery Mode
* **getExpiration()** - Expiration (integer, number of ms)
* **getHeaders()** - Struct containing any custom headers
* **getMessageId()** - Message ID
* **getPriority()** - Priority (numeric, 1-10)
* **getReplyTo()** - Reply to
* **getTimestamp()** - Timestamp (java.util.Date)
* **getType()** - Type
* **getUserId()** - User ID sending message

### Acknowledge Message

By default, messages will be automatically acknowledged, which removes them from the queue.  For transient, or unimportant messages, this is fine.  However, if you want to protect against an important
message getting lost, set `autoAcknowledge` to false when getting your message or starting the consumer and explicitly acknowledge it like so:

```js
message.acknowledge();
```

Do not call this method if `autoAcknowledge` is enabled, or you will receive an error.  

When you start a consumer thread, you can simply return `true` from your callback UDF to acknowledge the message as processed.

### Reject Message

If you are unable to process a message (such as a DB connection issue or other unrecoverable error) you can reject the message which will tell the Rabbit server that it was not processed.  

```js
message.reject();
```

Do not call this method if `autoAcknowledge` is enabled, or you will receive an error.  

When you start a consumer thread, you can simply return `false` from your callback UDF to reject the message.

The default behavior when rejecting a message is NOT to requeue the message, meaning it is lost.  If you want the message to be placed back in the queue for redelivery, then call reject like so:

```js
message.reject( requeue=true );
```

Be careful, as this can create a huge amount of traffic if the same failing message gets redelivered over and over again. 
You probably want to log when messages are rejected and redelivered so you can keep an eye on why it is happening.  

# Queue Management

You can create, remove, and purge queues from the channel API.

## Create a queue

Creating a queue is idempotent, meaning you can call this as many times as you like, and if the queue already exists, nothing happens.

```js
rabbitClient.queueDeclare( 'myQueue' );
```

Creating a queue has the following additional arguments

* **durable** - true if we are declaring a durable queue (the queue will survive a server restart)
* **exclusive** - true if we are declaring an exclusive queue (restricted to this connection)
* **autoDelete** - true if we are declaring an autodelete queue (server will delete it when no longer in use)

## Bind a queue

A queue binding controls what exchange and routing keys will deliver to the queue.

```js
rabbitClient
	.queueDeclare( 'myQueue' )
	.queueBind( queue='myQueue', exchange='amq.direct', routingKey='routing.key' );
```

## Delete queue

```js
rabbitClient.queueDelete( 'myQueue' );
```

Deleting a queue has the following additional arguments

* **ifUnused** - true if the queue should be deleted only if not in use
* **ifEmpty** - true if the queue should be deleted only if empty


## Purge queue

Purging a queue removes all messages.  This is probably only something you'd need for testing.

```js
rabbitClient.queuePurge( 'myQueue' );
```
	
## Check if queue exists

Returns true if queue exists, false if it doesn't.  Be careful calling this method under load as it catches a thrown exception if the queue doesn't exist 
so it probably doesn't perform great if the queue you are checking doesn't exist most of the time.

```js
var exists = rabbitClient.queueExists( 'myQueue' );
```

## Get count of messages in a queue

Returns count of the messages of the given queue.  Doesn't count messages which waiting acknowledges or published to queue during transaction but not committed yet.  

```js
var count = rabbitClient.getQueueMessageCount( 'myQueue' );
```

## Channel

All Rabbit interactions actually happen over a channel.  All of the methods on the rabbitClient CFC automatically create and close a channel on your behalf for every operation.
You can  also create your own channel to use directly so you can re-use it.  Do not share the same channel between threads.  The channel's are technically thread safe, but only one thread can use the channel at a time
so it would create an unwanted bottleneck.

```js
var channel = rabbitClient.createChannel();
```

Make sure to call `close()` on a channel when you're done.  This is important or the channel will be left open forever and there is a limited number of channels that can be open for a connection.
In case you're code errors, it is recommended to use a `finally` block to ensure the close always happens.

```js
try {
	var channel = rabbitClient.createChannel();
	channel.queueDeclare( 'myQueue' );	
} finally {
	channel.close();
}
```

The way AMQP works is that if any communication error happens, the channel will be automatically closed which means no more actions can be take with it.  Please account for this in your code and 
ask the client for a fresh channel if the previous one encounters an error.  



## Sponsorship

Initial development for this module sponsored by [Avoya Travel](https://avoyatravel.com).

********************************************************************************
Copyright Since 2005 ColdBox Framework by Luis Majano and Ortus Solutions, Corp
www.ortussolutions.com
********************************************************************************

#### HONOR GOES TO GOD ABOVE ALL

Because of His grace, this project exists. If you don't like this, then don't read it, its not for you.

> "Therefore being justified by faith, we have peace with God through our Lord Jesus Christ:
By whom also we have access by faith into this grace wherein we stand, and rejoice in hope of the glory of God.
And not only so, but we glory in tribulations also: knowing that tribulation worketh patience;
And patience, experience; and experience, hope:
And hope maketh not ashamed; because the love of God is shed abroad in our hearts by the 
Holy Ghost which is given unto us. ." Romans 5:5

### THE DAILY BREAD

 > "I am the way, and the truth, and the life; no one comes to the Father, but by me (JESUS)" Jn 14:1-12
