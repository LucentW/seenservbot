## seenservbot v0.1
## Requires editing to get this working correctly.
##
## Source is distributed under the AGPL v3.0
## https://www.gnu.org/licenses/agpl-3.0.html
##
## Contributions to the code are welcome.

require 'telegram/bot'
require 'redis'
require 'json'

## CONFIGURATION START ##
token = 'INSERT_YOUR_BOT_TOKEN_HERE'
## CONFIGURATION END ##

class String
  def is_number?
    true if Float(self) rescue false
  end
end

redis = Redis.new

Telegram::Bot::Client.run(token) do |bot|
  bot.listen do |message|
    text = nil

    case message.text
    when /^\/start$/i
      if message.chat.type == 'private'
        text = "Hello! I am *SeenServ*, a Telegram port of the homonymous"
        text << " service _commonly found on most IRC networks_.\n\n"
        text << "My database is contributed by *users like you* that add me"
        text << " to their groups so that I can store their users' _IDs, "
        text << "usernames and last seen message times_.\n\n"
        text << "I *will not* store any part of the conversations themselves, nor"
        text << " this private chat.\n\n"
        text << "My source code is *publicly viewable and auditable* on "
        text << "https://github.com/LucentW/seenservbot.\n"
        text << "Feel free to check it out and contribute to that! We love "
        text << "PRs and feedback!\n\n"
        text << "The main command is /seen followed by *an ID or a username* "
        text << "(including the @). I will try to do my best to crawl my "
        text << "database searching about your friend.\n"
        text << "You can *exclude yourself* from being indexed by using the "
        text << "commands /hideme and /showme."
      end
    when /^\/seen (.*)/
      puts "QUERY: User #{message.from.id} queried #{$1}"

      current_user = nil
      if $1.start_with?("@")
        current_user = JSON.parse(redis.get("username:#{$1[1..-1].downcase}")) rescue nil
      else
        if $1.is_number?
          current_user = JSON.parse(redis.get("id:#{$1}")) rescue nil
        else
          puts "DEBUG: User #{message.from.id} query is malformed"
          text = "Make sure to give me an *ID* or a *username* (including the @)."
        end
      end

      if !current_user.nil? then
        if redis.get("exclude:#{current_user["id"].to_s}").nil?
          puts "QUERY: Cache hit for #{message.from.id}'s query."
          text = "I found user "
          if current_user["username"].nil? then
            if current_user["last_name"].nil? then
              text << "_" << current_user["first_name"] + "_ \\[ " + current_user["id"].to_s + "]"
            else
              text << "_" << current_user["first_name"] + " " + current_user["last_name"] + "_ \\[ " + current_user["id"].to_s + "]"
            end
          else
            text << "@" + current_user["username"] + " \\[" + current_user["id"].to_s + "]"
          end
          text << " on my database.\n"

          last_seen = redis.get("id:#{current_user["id"].to_s}:last_seen")
          if !last_seen.nil?
            text << "*Last time* I heard him/her was on _"
            text << Time.at(last_seen.to_i).utc.to_s << "_."
          else
            puts "DEBUG: wtf no last seen for queried #{$1}"
            text << "I have *no clue* why I know him but I never heard him/her."
          end
        else
          puts "DEBUG: User #{$1} is self-hidden."
          text = "This user enabled *privacy mode*. I can't say _anything_ "
          text << " about him/her."
        end
      else
        if text.nil?
          puts "QUERY: Cache miss for #{message.from.id}'s query."
          text = "Unfortunately I have no clue about that username/ID."
        end
      end
    when /^\/seen$/
      text = "It looks like you forgot _who to search for_... *Check your query "
      text << "twice!*"
    when /^\/hideme$/
      text = "Added you to the exclude list."
      redis.set("exclude:#{message.from.id}", true)
    when /^\/showme$/
      text = "Removed you from the exclude list."
      redis.del("exclude:#{message.from.id}")
    else
      if redis.get("exclude:#{message.from.id}").nil?
        current_user = Hash.new
        current_user["id"] = message.from.id
        current_user["first_name"] = message.from.first_name
        current_user["last_name"] = message.from.last_name rescue nil
        current_user["username"] = message.from.username rescue nil
        real_current_user = current_user.to_json
        if !message.from.username.nil? then
          redis.set("username:#{message.from.username.downcase}", real_current_user)
        end
        redis.set("id:#{message.from.id}", real_current_user)
        redis.set("id:#{message.from.id}:last_seen", Time.now.to_i)

        puts "STORE: Got message from ID #{message.from.id}"
      else
        puts "DEBUG: Message from self-hidden user #{message.from.id}"
      end
    end

    if !text.nil?
      bot.api.send_message(chat_id: message.chat.id, text: text, reply_to_message_id: message.message_id, parse_mode: "Markdown") rescue puts "Bot blocked?"
    end
  end
end
