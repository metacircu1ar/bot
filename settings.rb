require 'set'
require 'tzinfo'

BOT_TOKEN_STRING = ''

# Set to false for testing.
# If set to true, destructive(writing) API calls for banning and messaging will be made.
# Non-destructive(reading) API calls are always allowed.
ENABLE_DESTRUCTIVE_API_CALLS = true

USER_RATE_LIMITS = [
  # Example user rate limit configuration:
  {
    # To specify the user, if the user has a username(for example Dok_zzz), use @Dok_zzz format.
    # Otherwise user id(for example 156111338) should be used with the ID:156111338 format.
    id: '@Dok_zzz',
    # Apply rule 0 from the RULE_LIST on all days, except for saturday and sunday.
    rule_by_weekday: [0,0,0,0,0,nil,nil]
  }
]

RULE_LIST = {
  # When rule 0 is applied, the user will be allowed to post 3 messages per 1 hour.
  0 => { period_duration_sec: 1 * 60 * 60, messages_limit: 3 }
}

# Specifies, in seconds, at which offset from 00:00 should the new day start.
# For example, if set to 4 hours, the new day will start at 04:00,
# so that 02:00 monday(actual MSK time) will be interpreted as
# 22:00 sunday during rule selection.
DAY_START_OFFSET_SEC = 4 * 60 * 60 # 4 hours

CHAT_ID = -1001098824720

ALLOWED_CHAT_IDS = [
  CHAT_ID
].to_set

BAN_REACTION_STICKER_IDS = [
  # Evil red doge
  "CAACAgEAAxkBAAJR0GURlhavuic8CjW8RntEHzI4TA6qAAI4AQACfvPIR6denfwffFuwMAQ",
  # Doge with a baseball bat
  "CAACAgEAAxkBAAJRzmURlUuFW58y8IUVAUmP7i2B3beUAALHAgACCHW3HmhSjGAVFofhMAQ",
  # Doge beating other doge with a baseball bat
  "CAACAgEAAxkBAAJRs2URbw9Og_G4TeLd0mcrKMEW13O1AAJlAwACCHW3HoCsWVVcN92rMAQ",
  # Doge in sunglasses
  "CAACAgEAAxkBAAJRsWURbiC73R0aSe6AwHLh0_CHgi9tAAJmAwACCHW3Hu144k0Q4KFgMAQ",
  # Worker doge in sunglasses
  "CAACAgEAAxkBAAJRtWURbx8clM9TD5IhOAXOK2KmVstpAAIxAwACCHW3HoavOO7H79sLMAQ",
  # Death doge
  "CAACAgEAAxkBAAJR0mURlseTh2BGyo3n1aekLRfy7aIxAAJiAwACCHW3HpE-tLsLQOKgMAQ",
  # Samurai doge with a katana
  "CAACAgEAAxkBAAJR1GURl01zNTHoB3JOE59X5ZQU_Kp5AAI0AwACCHW3HvnoVwYtJoCSMAQ"
]

TIMEZONE = TZInfo::Timezone.get('Europe/Moscow')

class BotToken
  attr_accessor :token

  def initialize(string)
    @token = string
  end
end

BOT_TOKEN = BotToken.new(BOT_TOKEN_STRING)
