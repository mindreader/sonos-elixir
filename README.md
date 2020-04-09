## The project

This is an attempt to interface programmatically with the sonos speakers.

There are other implementations for this, but they are very flaky and I think I can do better.

There have been rumbles from Sonos to stop supporting their older speakers (I don't blame them), and so this may someday become insurance against that.

There are also features I wish it supported that it doesn't.  Right now the speakers have to do a lot of heavy lifting of their own because they can't rely on your phone or computer to do the work for them.  I want the speakers to be "dumb" so that they will play audio from this service without needing to worry about anything.

## So far

* Discover speakers on your internal network without requiring you to configure your ip address.

## Roadmap

* Basic pause / play / skip functionality
* Volume control
* Periodically rediscover and remove non responsive speakers.
* Subscribe to speakers and monitor their current states
* Speaker groups
* Play audio from local files using this as its own music source
* Proxy audio to other services to allow for caching of audio, statistics gathering
* Better support for podcasts (podcasts really suck in the sonos app)
* API to aid in implementing a dashboard.

## To investigate

* Is it possible to auto configure speakers to use this as an audio source?
