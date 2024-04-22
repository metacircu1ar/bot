# bot
## Dependencies
```
gem install tzinfo
gem install telegram-bot-ruby
gem install activesupport
```
## Bot token
There are 3 ways to specify the bot token.
- Specify `BOT_TOKEN` as an environment variable:
```
BOT_TOKEN="YOUR_TOKEN_STRING" ruby bot.rb
```
- Pass your bot token string as a command line argument:
```
ruby bot.rb YOUR_TOKEN_STRING
```
- Speicify `BOT_TOKEN_STRING` in `settings.rb`

## Commands
To run a command, any chat admin should send a message to the chat, containing one the following commands.
- `/enable_flood` (or `/flood_enable`)  
Disables the bot until the next day. Turns off the message rate limiter.
- `/flood_disable` (or `/disable_flood`)  
Enables the bot. Turns on the message rate limiter.
- `/bot_please_die`  
Kills the bot process on the server.

## How to enable the bot for your chat
1. Include your telegram chat id into `ALLOWED_CHAT_IDS` in `settings.rb`.
2. Specify the user rate limits, see `USER_RATE_LIMITS` in `settings.rb` as an example.
3. Specify the rules, see `RULE_LIST` in `settings.rb` as an example.
4. Specify other constants in `settings.rb` if needed.
5. Create the rate limiter, see `bot.rb`(inside the `run_bot` function) or see the complete example below.  

```ruby
YOUR_TELEGRAM_CHAT_ID = -1234567989

ALLOWED_CHAT_IDS = [
  YOUR_TELEGRAM_CHAT_ID
].to_set

# See USER_RATE_LIMITS in settings.rb for the detailed explanation.
USER_RATE_LIMITS = [
  {
    id: '@UsernameOfSomeoneYouWantToLimit', # Also the user can be specified by user id, see settings.rb.
    rule_by_weekday: [0,0,0,0,0,nil,nil]
  },
  {
    id: '@UsernameOfSomeoneElseYouWantToLimit',
    rule_by_weekday: [0,0,0,0,0,nil,nil]
  }
]

# See RULE_LIST in settings.rb for the detailed explanation.
RULE_LIST = {
  0 => { period_duration_sec: 1 * 60 * 60, messages_limit: 1 }
}

# In bot.rb:
def run_bot(rate_limiters)
  rate_limiters = Hash.new
  rate_limiters[YOUR_TELEGRAM_CHAT_ID] = RateLimiter.new(USER_RATE_LIMITS, RULE_LIST)
  ...

# Run the bot:
BOT_TOKEN="YOUR_BOT_TOKEN" ruby bot.rb  
```
