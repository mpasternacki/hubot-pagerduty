module.exports = (robot) ->
  path = require('path')
  robot.load path.resolve "node_modules", "hubot-pagerduty", "src", "scripts"
