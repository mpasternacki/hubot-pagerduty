#
# Pager Duty Integration
#
# Commands:
# hot oncall - list of people on call and the schedules they're assigned to.
#
# Additionally polls for active incidents every 30 seconds, and relays them to
# the "incident room".
#
# Authored by the Hotel Tonight Team.
# Please see LICENSE file for distribution terms.
#

fs = require('fs')
config = JSON.parse(fs.readFileSync("pagerdutyrc"))

token       = config.token
schedules   = config.schedules
subdomain   = config.api_subdomain

incident_poll_interval  = 30000 # once every 30 seconds
incident_timeout        = 300000 # 5 minutes in milliseconds

# XXX had to code dive for this, might be hipchat specific.
incident_room = { "reply_to": config.incident_room }

seen_incidents = { }

# this is seriously some ghetto shit. if someone else knows how to make it
# better, please do. -erikh
getTextDate = (date) ->
  month = date.getMonth() + 1
  day = date.getDate()
  today = "#{date.getFullYear()}-"

  if month < 10
    month = "0#{month}"
  else
    month = "#{month}"

  if day < 10
    day = "0#{day}"
  else
    day = "#{day}"

  today += "#{month}-#{day}"
  return today

getFetcher = (schedule, func) ->
  return (msg, today, tomorrow) ->
    schedule_name = schedule[0]
    schedule_id   = schedule[1]
    msg
      .http("https://#{subdomain}.pagerduty.com/api/v1/schedules/"+schedule_id+"/entries")
      .query
        since: getTextDate(today)
        until: getTextDate(tomorrow)
      .headers
        "Content-type": "application/json"
        "Authorization": "Token token=" + token
      .get() (err, res, body) ->
        result = JSON.parse(body)
        msg.send "#{schedule_name}: #{result.entries[0].user.name}" 
        func(msg, today, tomorrow) if func?

checkIncidents = (robot) ->
  today = new Date()
  tomorrow = new Date(today.getTime() + 86400000)
  robot 
    .http("https://#{subdomain}.pagerduty.com/api/v1/incidents")
    .query
      since: today
      until: tomorrow
      status: "triggered"
    .headers
      "Content-type": "application/json"
      "Authorization": "Token token=" + token
    .get() (err, res, body) ->
      processing_time = new Date().getTime()
      result = JSON.parse(body)
      for incident in result.incidents
        last_seen = seen_incidents[incident.incident_number]
        if !last_seen? || processing_time - incident_timeout > last_seen
          strings = ["PagerDuty Alert: #{incident.incident_key} - URL: #{incident.html_url}"]
          if incident.assigned_to_user?
            strings.push(" Assigned To: #{incident.assigned_to_user.name}")
          robot.send(incident_room, strings)
          seen_incidents[incident.incident_number] = processing_time
        # make an attempt to cleanup stuff we'll never see again
        for num, time of seen_incidents
          if processing_time - incident_timeout > time 
            delete seen_incidents[num]

module.exports = (robot) ->
  setInterval(checkIncidents, incident_poll_interval, robot)
  robot.respond /oncall/i, (msg) ->
    today = new Date()
    tomorrow = new Date(today.getTime() + 86400000)
    msg.send "Oncall schedule for #{getTextDate(today)} - #{getTextDate(tomorrow)}:"
    # make an attempt to do this synchronously
    sync_call = null
    for schedule in schedules.reverse()
      do (schedule) ->
        sync_call = getFetcher(schedule, sync_call)
    sync_call(msg, today, tomorrow)
