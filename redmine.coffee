# Description
#   A Hubot script for redmine
#
# Configuration:
#   HUBOT_REDMINE_API_KEY
#   HUBOT_REDMINE_ADMIN_GROUP
#   HUBOT_REDMINE_ANNOUNCE_CHANNEL
#   HUBOT_REDMINE_REDMINE_URL
#   HUBOT_REDMINE_DAILY_URL
#   HUBOT_REDMINE_WEEKLY_URL
#
# Commands:
#   hubot daily - view daily agenda
#   hubot weekly - view weekly agenda
#
# Author:
#   hidepin <hidepin@gmail.com>

config =
  api_key: process.env.HUBOT_REDMINE_API_KEY
  admin_group: process.env.HUBOT_REDMINE_ADMIN_GROUP
  announce_channel: process.env.HUBOT_REDMINE_ANNOUNCE_CHANNEL
  redmine_url: process.env.HUBOT_REDMINE_REDMINE_URL
  daily_url: process.env.HUBOT_REDMINE_DAILY_URL
  weekly_url: process.env.HUBOT_REDMINE_WEEKLY_URL

assigned_user = (issue) ->
  if issue.assigned_to?
    issue.assigned_to
  else
    issue.author

is_expired = (date) ->
  return false unless date?
  expired_date = new Date(date)
  today = new Date()
  today > expired_date

module.exports = (robot) ->
  robot.hear /HEY/i, (msg) ->
    msg.send('hey')

  unless config.api_key? and
         config.admin_group? and
         config.announce_channel? and
         config.redmine_url? and
         config.daily_url? and
         config.weekly_url?
    robot.logger.error 'process.env.HUBOT_REDMINE_XXX is not defined'
    return

  robot.respond /DAILY$/i, (msg) ->
    if msg.message.room is config.announce_channel
      msg.http("#{config.daily_url}?key=#{config.api_key}").get() (err, res, body) ->
        parse_body = JSON.parse body
        msg.send(parse_body.wiki_page.text);

  robot.respond /WEEKLY$/i, (msg) ->
    if msg.message.room is config.announce_channel
      msg.http("#{config.weekly_url}?key=#{config.api_key}").get() (err, res, body) ->
        parse_body = JSON.parse body
        msg.send(parse_body.wiki_page.text);

  robot.respond /TASKLIST$/i, (msg) ->
    if msg.message.room is config.announce_channel
      redmine_groups = msg.http("#{config.redmine_url}/groups.json?key=#{config.api_key}").get() (err, res, body) ->
        parse_body = JSON.parse body

        for group in parse_body.groups
          if group.name is config.admin_group
            g_id = group.id
            msg.http("#{config.redmine_url}/groups/#{g_id}.json?include=users&key=#{config.api_key}").get() (err, res, body) ->
              groups_parse_body = JSON.parse body
              if groups_parse_body.group.users.length > 0
                msg.http("#{config.redmine_url}/issues.json?status_id=*&key=#{config.api_key}").get() (err, res, body) ->
                  tasks = {}
                  for user in groups_parse_body.group.users
                    tasks[user.name] = {
                                        "active": 0
                                        "expired": 0
                                        "closed": 0
                                       }
                  issues = JSON.parse body
                  for issue in issues.issues
                    user = assigned_user issue
                    if user.name of tasks == true
                      if issue.status.name is "終了" or issue.status.name is "closed"
                        tasks[user.name]['closed']++
                      else
                        tasks[user.name]['active']++
                        tasks[user.name]['expired']++ if is_expired(issue.due_date)
                  issue_url = "#{config.redmine_url}/issues?set_filter=1&sort=priority:desc,due_date:asc,updated_on:desc&assigned_to_id="
                  tasklist = "|ユーザ名|未完了タスク|期限切れタスク|完了済みタスク|\n"
                  tasklist += "|:---|:---:|:---:|:---:|\n"
                  tasklist += ("|#{user.name}|[#{tasks[user.name]['active']}](#{issue_url}#{user.id}&status_id=open)|[#{tasks[user.name]['expired']}](#{issue_url}#{user.id}&status_id=open&op[due_date]=<t-&v[due_date])|[#{tasks[user.name]['closed']}](#{issue_url}#{user.id}&status_id=closed)|\n" for user in groups_parse_body.group.users).sort().join('')
                  msg.send(tasklist)
