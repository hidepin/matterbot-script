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
#   hubot tasklist - view task list
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
  issue_list_limit: 100

class Tasks
  constructor: ->
    @msg
    @tasks = {}

  set_msg: (msg) ->
    @msg = msg

  set_user: (uname) ->
    @tasks[uname] = new Task

  get_user: (uname) ->
    @tasks[uname]

class Task
  constructor: ->
    @active = 0
    @expired = 0
    @closed = 0

  countup_active: ->
    @active++

  countup_expired: ->
    @expired++

  countup_closed: ->
    @closed++

assigned_user = (issue) ->
  if issue.assigned_to?
    issue.assigned_to
  else
    issue.author

is_expired = (date) ->
  return false unless date?
  expired_date = new Date(date + " 23:59:59")
  today = new Date()
  today > expired_date

get_status = (expired) ->
  if expired > 0
    ":cold_sweat:"
  else
    ":smile:"

tasklist_header = ->
  tasklist_h = "|ユーザ名|ステータス|未完了タスク|期限切れタスク|完了済みタスク|\n"
  tasklist_h += "|:---|:---:|:---:|:---:|:---:|\n"
  tasklist_h

send_tasklist = (tasks,users) ->
  issue_url = "#{config.redmine_url}/issues?set_filter=1&sort=priority:desc,due_date:asc,updated_on:desc&f[]=status_id&f[]=assigned_to_id&op[assigned_to_id]==&v[assigned_to_id][]="
  tasklist = tasklist_header()
  tasklist += ("|#{user.name}|#{get_status(tasks.get_user(user.name).expired)}|[#{tasks.get_user(user.name).active}](#{issue_url}#{user.id}&op[status_id]=o)|[#{tasks.get_user(user.name).expired}](#{issue_url}#{user.id}&&op[status_id]=o&f[]=due_date&op[due_date]=<t-&v[due_date][]=1)|[#{tasks.get_user(user.name).closed}](#{issue_url}#{user.id}&op[status_id]=c)|\n" for user in users).sort().join('')
  tasks.msg.send(tasklist)

view_tasklist = (tasks, pages, users) ->
  if pages is 0
    send_tasklist(tasks, users)
  else
    tasks.msg.http("#{config.redmine_url}/issues.json?status_id=*&limit=100&page=#{pages}&key=#{config.api_key}").get() (err, res, body) ->
      issues = JSON.parse body
      for issue in issues.issues
        user = assigned_user issue
        if tasks.get_user(user.name)?
          if issue.status.name is "終了" or issue.status.name is "却下"
            tasks.get_user(user.name).countup_closed()
          else
            tasks.get_user(user.name).countup_active()
            tasks.get_user(user.name).countup_expired() if is_expired(issue.due_date)
      view_tasklist(tasks, pages - 1, users)

module.exports = (robot) ->
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
      msg.http("#{config.redmine_url}/groups.json?key=#{config.api_key}").get() (err, res, body) ->
        redmine_groups = JSON.parse body

        for group in redmine_groups.groups
          if group.name is config.admin_group
            msg.http("#{config.redmine_url}/groups/#{group.id}.json?include=users&key=#{config.api_key}").get() (err, res, body) ->
              group_users = JSON.parse body
              if group_users.group.users.length > 0
                msg.http("#{config.redmine_url}/issues.json?status_id=*&limit=#{config.issue_list_limit}&key=#{config.api_key}").get() (err, res, body) ->
                  tasks = new Tasks
                  tasks.set_msg(msg)
                  for user in group_users.group.users
                    tasks.set_user(user.name)

                  total_count = JSON.parse(body).total_count

                  view_tasklist(tasks, Math.ceil(total_count / 100), group_users.group.users)
