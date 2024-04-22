require_relative 'settings'

require 'telegram/bot'
require 'active_support/all'
require 'ostruct'
require 'tzinfo'
require 'set'

module ResultCommon
  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    def [](*args)
      new(*args)
    end
  end

  attr_reader :message, :data

  def initialize(message = "", data = {})
    @message = message
    @data = OpenStruct.new(data)
  end
end

class Ok
  include ResultCommon
end

class Error
  include ResultCommon
end

def run_reading_api_call
  puts "Running reading API call."

  begin
    yield
  rescue => exception
    puts "Exception:"
    pp exception
  end
end

def run_destructive_api_call
  puts "Running destructive API call."

  if !ENABLE_DESTRUCTIVE_API_CALLS
    puts "Destructive API calls are disabled, skipping."
    return
  end

  begin
    yield
  rescue => exception
    puts "Exception:"
    pp exception
  end
end

def pluralize(string, count)
  string + (count != 1 ? "s" : "")
end

class RateLimiter
  def initialize(user_configs, rule_list)
    @user_limits = Hash.new
    @rule_list = rule_list
    @flood_enabled = false
    @flood_enabled_start_unix_time = 0
    @user_count = user_configs.size

    user_configs.each do |config|
      @user_limits[config[:id]] =
        reset_user_limit_state(config.slice(:rule_by_weekday))
    end
  end

  def execute(message)
    current_time, offset_time, current_week_day, offset_week_day = get_current_time_info

    puts "Current time(MSK): #{current_time}"
    puts "Offset time: #{offset_time}"
    puts "Current week day: #{current_week_day}"
    puts "Offset week day: #{offset_week_day}"

    if maybe_disable_flood(current_time)
      return Ok["Flood is enabled, allowing the message."]
    end

    make_keys = lambda do |user_name, user_id|
      has_username = !user_name.nil? && !user_name.empty?
      [has_username ? "@#{user_name}" : nil, "ID:#{user_id}"]
    end

    user_name, user_id = message.from.username, message.from.id
    user_name_key, user_id_key = make_keys[user_name, user_id]

    user_limit = nil

    # Look up user by user id first, then by user name(if it exists).
    user_limit = @user_limits[user_id_key]
    user_limit = @user_limits[user_name_key] if user_limit.nil? && !user_name_key.nil?

    # If user is not in the configuration, allow the message.
    return Ok["User is not in the configuration"] if user_limit.nil?

    rule_table = user_limit[:rule_by_weekday]
    # Select the rule by offset week day, not current day.
    rule_name = rule_table[offset_week_day]

    # If there is no rule to apply on current day, allow the message.
    return Ok["There is no rule to apply on current day"] if rule_name.nil?

    puts "Rule name: #{rule_name}"

    rule = @rule_list[rule_name]

    # If there is no corresponding rule from the rule list, allow the message.
    return Ok["Rule #{rule_name} is missing from the rule list"] if rule.nil?

    puts "Rule: #{rule.inspect}"

    last_period_start_unix_time = user_limit[:last_period_start_unix_time]
    period_duration_sec = rule[:period_duration_sec]
    current_unix_time = current_time.to_i

    # Check if the time duration has elapsed since
    # the start of the last period or if the week day has changed.
    if last_period_start_unix_time.nil? ||
       get_day_start_for(last_period_start_unix_time) != get_day_start_for(current_unix_time) ||
       ((current_unix_time - last_period_start_unix_time) >= period_duration_sec)
      user_limit[:last_period_start_unix_time] = current_unix_time
      user_limit[:message_count] = 1
      Ok["Starting the new peroid on #{current_time}, messages posted: " +
         "#{user_limit[:message_count]}, messages limit: #{rule[:messages_limit]}"]
    else
      # Check if the message limit has been exceeded.
      if user_limit[:message_count] < rule[:messages_limit]
        user_limit[:message_count] += 1
        Ok["Messages posted: #{user_limit[:message_count]}, messages limit: #{rule[:messages_limit]}"]
      else
        # User has exceeded the message limit and should be restricted from posting.
        restriction_end_date_unix_time = last_period_start_unix_time + period_duration_sec

        # https://core.telegram.org/tdlib/docs/classtd_1_1td__api_1_1chat_member_status_banned.html
        # Quote:
        ### If the user is banned for more than 366 days or for less than 30 seconds from the current time,
        ### the user is considered to be banned forever.

        # To avoid the corner case of user exceeding the message limit <= 30 seconds before
        # the end of his period and getting incorrectly permabanned, ban for at least a minute from current time.

        restriction_end_date_unix_time = [restriction_end_date_unix_time, current_unix_time + 60].max
        ban_duration_sec = restriction_end_date_unix_time - current_unix_time

        reset_user_limit_state(user_limit)

        end_date = unix_time_to_local_time(restriction_end_date_unix_time)

        Error["Created restriction end date: #{end_date}", {
          restriction_end_date_unix_time: restriction_end_date_unix_time,
          ban_duration_sec: ban_duration_sec,
          messages_limit: rule[:messages_limit],
          period_duration_sec: rule[:period_duration_sec],
          user_count: @user_count
        }]
      end
    end
  end

  def enable_flood_until_next_day
    current_time, _, _, _ = get_current_time_info
    current_unix_time = current_time.to_i

    time_day_from_now = current_unix_time + (24 * 60 * 60)
    next_day_start_time = get_day_start_for(time_day_from_now)
    format_string = '%d-%B-%Y %H:%M'
    flood_end_time = unix_time_to_local_time(next_day_start_time).strftime(format_string)

    if @flood_enabled
      flood_start_time = unix_time_to_local_time(@flood_enabled_start_unix_time).strftime(format_string)
      return Error["Flood was already enabled on #{flood_start_time} MSK until #{flood_end_time} MSK."]
    end

    @flood_enabled_start_unix_time = current_unix_time
    @flood_enabled = true

    # Reset the current state of all users.
    @user_limits.each { |id, user_limit| reset_user_limit_state(user_limit) }

    puts "Enabling flood until the next day. "
    puts "Current time: #{current_time}"

    Ok["Ok. Flood is enabled until #{flood_end_time} MSK."]
  end

  def disable_flood
    puts "Disabling flood."
    @flood_enabled = false
    @flood_enabled_start_unix_time = 0
  end

  private

  def get_current_time_info
    current_time = TIMEZONE.now
    offset_time = current_time - DAY_START_OFFSET_SEC
    # Remap the default wday 0-6(sun-sat) range to 0-6(mon-sun).
    current_week_day = current_time.wday == 0 ? 6 : current_time.wday - 1
    offset_week_day = offset_time.wday == 0 ? 6 : offset_time.wday - 1
    [current_time, offset_time, current_week_day, offset_week_day]
  end

  def maybe_disable_flood(current_time)
    current_unix_time = current_time.to_i
    if @flood_enabled &&
       get_day_start_for(@flood_enabled_start_unix_time) != get_day_start_for(current_unix_time)
      disable_flood
    end
    @flood_enabled
  end

  def reset_user_limit_state(user_limit)
    user_limit[:last_period_start_unix_time] = nil
    user_limit[:message_count] = 0
    user_limit
  end

  def get_day_start_for(unix_time)
    unix_time = unix_time - DAY_START_OFFSET_SEC
    day_start_unix_time = unix_time_to_local_time(unix_time).beginning_of_day.to_i
    day_start_unix_time + DAY_START_OFFSET_SEC
  end

  def unix_time_to_local_time(unix_time)
    Time.at(unix_time).in_time_zone(TIMEZONE)
  end
end

trap('INT') do
  puts "\nCtrl+C detected. Exiting..."
  exit 1
end

if BOT_TOKEN.token.nil? || BOT_TOKEN.token.empty?
  puts "Bot token is empty in settings.rb"
  puts "Trying to read BOT_TOKEN env variable..."

  BOT_TOKEN.token = ENV['BOT_TOKEN']

  if BOT_TOKEN.token.nil?
    puts "BOT_TOKEN environment variable is not set."
    puts "Trying to extract BOT_TOKEN from command line arguments..."
    BOT_TOKEN.token = ARGV[0]
  end

  if BOT_TOKEN.token.nil?
    puts "BOT_TOKEN was not passed as a command line argument."
    puts "Either provide BOT_TOKEN env variable or pass the bot token as a command line argument."
    exit(1)
  end
end

def run_bot(rate_limiters)
  Telegram::Bot::Client.run(BOT_TOKEN.token) do |bot|
    chat_admin_cache = Hash.new

    bot_start_time = TIMEZONE.now
    bot_start_unix_time = bot_start_time.to_i

    puts "Bot is listening to messages..."
    puts "Bot start time(MSK): #{bot_start_time}"
    puts "Destructive(writing) API calls: #{ENABLE_DESTRUCTIVE_API_CALLS ? "enabled" : "disabled"}"

    bot.listen do |message|
      case message
      when Telegram::Bot::Types::Message
        chat_id, chat_title = message.chat.id, message.chat.title

        puts "*******************************************************"
        puts "Chat title: \"#{chat_title}\", chat id: #{chat_id}"

        if !ALLOWED_CHAT_IDS.include?(chat_id)
          puts "Chat is not in ALLOWED_CHAT_IDS, skipping the message."
          puts "Notifying the chat to remove me."
          run_destructive_api_call do
            bot.api.send_message(
              chat_id: chat_id,
              text: "I am not allowed in this chat. Please remove me."
            )
          end
          next
        end

        # Skip all the messages posted before the bot joined the chat.
        if message.date <= bot_start_unix_time
          puts "Skipping old message. Message time #{message.date}, bot start time: #{bot_start_unix_time}"
          next
        end

        # When the message is edited, the bot receives it as a new message.
        # We need to count unique messages only, so we skip all message editing events.
        if !message.edit_date.nil?
          puts "Skipping message editing event."
          next
        end

        user_name, user_id, chat_id = message.from.username, message.from.id, message.chat.id

        puts "Executing the rate limiter:"
        puts "User name: #{user_name}, user id: #{user_id}"
        puts "Message text:"
        puts message.text
        puts "Message caption:"
        puts message.caption
        puts "Full message:"
        pp message
        puts "*******************************************************"

        limiter = rate_limiters[chat_id]

        if limiter.nil?
          puts "Rate limiter for this chat doesn't exist, create it."
          next
        end

        if !chat_admin_cache[chat_id]
          puts "Getting the list of admins for the chat."
          run_reading_api_call do
            admins = bot.api.get_chat_administrators(chat_id: chat_id)

            admin_infos =
              admins['result']
              &.filter_map{ |admin|
                admin['user']['is_bot'] ?
                  nil
                  :
                  [admin['user']['id'].to_i, admin['user']] }.to_h

            puts "Non-bot admins: #{admin_infos&.inspect}"
            chat_admin_cache[chat_id] = admin_infos
          end
        end

        if chat_admin_cache[chat_id]&.include?(user_id)
          run_admin_logic = lambda do |bot, message, limiter, admin|
            # Some messages have no text, but only caption.
            contents = message.text || message.caption || ""

            if contents.include?("/bot_please_die")
              puts "Notifying the admin of my untimely death."
              puts "Killed by: #{admin&.inspect}"

              run_destructive_api_call do
                bot.api.send_message(
                  chat_id: message.chat.id,
                  reply_to_message_id: message.message_id,
                  text: "Ok."
                )
              end
              exit(1)
            elsif contents.include?("/enable_flood") || contents.include?("/flood_enable")
              puts "Notifying the admin by sending the message to chat."

              result = limiter.enable_flood_until_next_day

              run_destructive_api_call do
                bot.api.send_message(
                  chat_id: message.chat.id,
                  reply_to_message_id: message.message_id,
                  text: result.message
                )
              end
            elsif contents.include?("/disable_flood") || contents.include?("/flood_disable")
              puts "Notifying the admin by sending the message to chat."

              limiter.disable_flood

              run_destructive_api_call do
                bot.api.send_message(
                  chat_id: message.chat.id,
                  reply_to_message_id: message.message_id,
                  text: "Ok. Flood is disabled."
                )
              end
            end
          end

          puts "User is a non-bot admin, skipping the message, running admin logic."
          run_admin_logic[bot, message, limiter, chat_admin_cache[chat_id][user_id]]
          next
        end

        result = limiter.execute(message)

        case result
        when Ok
          puts "Message is allowed: #{result.message}"
        when Error
          puts "Message limit exceeded: #{result.message}"

          seconds_to_timestring = lambda do |duration|
            seconds_in_a_day, seconds_in_an_hour = (60 * 60 * 24), (60 * 60)
            days = (duration / seconds_in_a_day).to_i
            hours = ((duration % seconds_in_a_day) / seconds_in_an_hour).to_i
            minutes = ((duration % seconds_in_an_hour) / 60).to_i
            [days, hours, minutes]
              .zip(["day", "hour", "minute"])
              .filter_map{ |n, s| n.zero? ? nil : "#{n} #{pluralize(s, n)}" }
              .join(", ")
          end

          data = result.data
          ban_duration_string = seconds_to_timestring[data.ban_duration_sec]

          puts "Ban duration: #{ban_duration_string}"

          run_destructive_api_call do
            bot.api.restrict_chat_member(
              chat_id: chat_id,
              user_id: user_id,
              until_date: data.restriction_end_date_unix_time, # Restrict until specified date
              permissions: {
                can_send_messages: false,
                can_send_media_messages: false,
                can_send_other_messages: false,
                can_add_web_page_previews: false
              }
            )

            period_duration_string = seconds_to_timestring[data.period_duration_sec]
            messages_limit = data.messages_limit

            ban_message = <<~MESSAGE
              Temporary read-only mode for #{ban_duration_string}, reason: exceeded
              the message rate limit of #{messages_limit} #{pluralize("message", messages_limit)}
              per #{period_duration_string}
              (#{data.user_count} #{pluralize("user", data.user_count)} in the list).
              Rules are not enforced on weekends.
            MESSAGE

            ban_message = ban_message.gsub(/\n/, ' ')

            bot.api.send_message(
              chat_id: chat_id,
              text: ban_message,
              reply_to_message_id: message.message_id
            )

            bot.api.send_sticker(
              chat_id: chat_id,
              sticker: BAN_REACTION_STICKER_IDS.sample
            )
          end
        end
      end
    end
  end
end

def main_loop
  rate_limiters = Hash.new
  rate_limiters[CHAT_ID] = RateLimiter.new(USER_RATE_LIMITS, RULE_LIST)
  loop do
    begin
      run_bot(rate_limiters)
    rescue => exception
      puts "Exception in the main loop:"
      pp exception
      sleep_time = 5 * 60
      puts "Sleeping for #{sleep_time} seconds..."
      sleep(sleep_time)
    end
  end
end

main_loop

