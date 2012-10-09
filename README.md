A PagerDuty Hubot Module
-------------------------

[PagerDuty](http://www.pagerduty.com) is a service that aggregates your
alerting systems and routes them. For example, you can get an alert from nagios
that goes to your Operations team, and another from Airbrake that gets sent to
your devs.

What this script does is integrate your
[Hubot](https://github.com/github/hubot) with the [PagerDuty
API](http://developer.pagerduty.com/).

It provides a few features:

* Ability to retrieve oncall rotation list for the current time
* Poll for incoming incidents and send a message to an "incident room" (e.g., the Operations or Dev Team Rooms) with details.

More features are coming. This was initially developed in house to scratch an
itch, and others have expressed interest in making use of it.

Requirements and Installation
-----------------------------

`npm install hubot-pagerduty`

You will also need to create a `pagerdutyrc` at the root of your hubot's path.
This is a JSON object and consists of a few fields:

* `token`: the API token you will use
* `api_subdomain`: the pagerduty subdomain. If you use `foo.pagerduty.com` to login, this will be `foo`.
* `schedules`: this is an array of two-element arrays. Position 0 is the schedule name, and position 1 is the schedule ID. If you go to the pagerduty website and look at a schedule, this will be the 6 digit alphanumeric code in the URL.
* `incident_room`: this is room ID to send notifications on incoming alerts, and will be specific to your chat medium.

This is parsed with `JSON.parse` which does not allow comments. You've been warned!

Your file should look something like this:

```
{
    "token": "a_big_string_of_characters",
    "schedules": [
      [ "Level 1", "ABCDEFG" ],
      [ "Level 2", "HIJKLMN" ],
      [ "Level 3", "OPQRSTU" ],
      [ "Level 4", "VWXYZ12" ]
    ],
    "incident_room": "1234_xyz@conf.hipchat.com",
    "api_subdomain": "mommas-basement"
}
```

Authors
-------

Hotel Tonight (www.hoteltonight.com) whipped this up. See the LICENSE file for
distribution details.

Contributing
------------

* Fork the project
* Make your changes.
  * Metadata changes such as to the license and authorship information will be
    rejected regardless how good your patch is.
* Send a pull request to this repository with a friendly hello.
* Have a beer.
