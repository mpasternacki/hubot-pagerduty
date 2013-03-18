#
# Pager Duty Integration
#
# Commands:
# hubot oncall - list of people on call and the schedules they're assigned to.
# hubot urgent <some text here> - send an urgent page for when the monitoring system fails - see README
# hubot resolve <id> - resolve an incident
# hubot acknowledge <id> - acknowledge an incident
# hubot override <minutes> <user> - override all the schedules for x minutes to user. Default user is the one saying it, and 60 minutes.
#

fs = require('fs')
config = JSON.parse(fs.readFileSync("pagerdutyrc"))

token     = config.token
schedules = config.schedules
subdomain = config.api_subdomain
user_map  = config.user_map

urgent_page_service_key = config.urgent_page_service_key

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

# more ghetto shit -erikh
getUTCTextTime = (date) ->
  month = date.getUTCMonth() + 1
  day = date.getUTCDate()
  today = "#{date.getUTCFullYear()}-"
  hours = date.getUTCHours()
  minutes = date.getUTCMinutes()

  # this is pretty horrible
  if hours < 10
    hours = "0#{hours}"
  else
    hours = "#{hours}"

  if minutes < 10
    minutes = "0#{minutes}"
  else
    minutes = "#{minutes}"

  if month < 10
    month = "0#{month}"
  else
    month = "#{month}"

  if day < 10
    day = "0#{day}"
  else
    day = "#{day}"

  today += "#{month}-#{day}T#{hours}:#{minutes}Z"
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

setOverride = (msg, time, userid) ->
  msg
    .http("https://#{subdomain}.pagerduty.com/api/v1/schedules")
    .query
      "requester_id": userid
    .headers
      "Content-type": "application/json"
      "Authorization": "Token token=" + token
    .get() (err, res, body) ->
      result = JSON.parse(body)
      if result.schedules?
        now = new Date()
        start = getUTCTextTime(now)
        end = getUTCTextTime(new Date(now.getTime() + (time * 60000)))
        data = { 
          "override": { "user_id": userid, "start": start, "end": end }
        }

        string_data = JSON.stringify(data)
        content_length = string_data.length

        for schedule in result.schedules
          do (schedule) ->
            msg
              .http("https://#{subdomain}.pagerduty.com/api/v1/schedules/#{schedule.id}/overrides")
              .headers
                "Content-type": "application/json"
                "Authorization": "Token token=" + token
                "Content-Length": content_length
              .post(string_data) (err, res, body) ->
                override_result = JSON.parse(body) 
                if override_result && override_result.override && !override_result.override.error?
                  msg.send "Override set #{schedule.name} from #{start} to #{end}"
                else
                  msg.send "Error setting override for #{schedule.name} from #{start} to #{end}"

updateIncident = (msg, id, status) ->
  data = { 
    "requester_id": user_map[msg.message.user.name], 
    "incidents": [ { "id": id, "status": status + "d" } ]
  }

  string_data = JSON.stringify(data)
  content_length = string_data.length
  msg
    .http("https://#{subdomain}.pagerduty.com/api/v1/incidents")
    .headers
      "Content-type": "application/json"
      "Content-Length": content_length
      "Authorization": "Token token=" + token
    .put(string_data) (err, res, body) ->
      result = JSON.parse(body)
      if result && result.incidents && result.incidents[0] && !result.incidents[0].error?
        msg.send "#{id} was set to #{status}d"
      else
        msg.send "There was an error handling your request to set #{id} to #{status}"

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
          strings = ["PagerDuty Alert: #{incident.trigger_summary_data.description || incident.trigger_summary_data.subject || incident.incident_key} - Incident ID: #{incident.id}"]
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

  robot.respond /(resolve|acknowledge)d?\s+(.*)/i, (msg) ->
    action = msg.match[1]
    incident_id = msg.match[2]
    updateIncident(msg, incident_id, action)

  robot.respond /override\s*(\S*)\s*(\S*)/i, (msg) ->
    time = msg.match[1] || 60
    user_id = user_map[msg.match[2]] || user_map[msg.message.user.name]
    setOverride(msg, time, user_id)

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

  robot.respond /urgent (.*)/i, (msg) ->
    incident_message = msg.match[1]
    curtime = new Date().getTime()
    reporter = msg.message.user.name
    query = {
        "service_key": urgent_page_service_key,
        "incident_key": "hubot/#{curtime}",
        "event_type": "trigger",
        "description": "Urgent from #{reporter}: #{incident_message}"
    }
    string_query = JSON.stringify(query)
    content_length = string_query.length
    msg
      .http("https://events.pagerduty.com/generic/2010-04-15/create_event.json")
      .headers
        "Content-type": "application/json",
        "Content-length": content_length
      .post(string_query) (err, res, body) ->
        result = JSON.parse(body)
        if result.status == "success"
          msg.send "Your page has been sent. Please be patient as it may be a minute or two before the recipient gets alerted."
        else
          msg.send "There was an error sending your page."
