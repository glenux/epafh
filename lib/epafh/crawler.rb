
require 'ruby-progressbar'

class Epafh::Crawler
	attr_reader :imap
	attr_reader :contacts

	TMPMAIL_FILE = '.tmpmail'
	MAIL_REGEXP = /\b[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,4}\b/

	def initialize config
    @saved_key = 'RFC822'
    @filter_headers = 'BODY[HEADER.FIELDS (FROM TO Subject)]'.upcase
		@config = config
		@imap = nil
		@contact_manager = Epafh::ContactManager.new config
	end

	def connect!
    @imap = Net::IMAP.new(
			@config[:imap][:server], 
			ssl: {verify_mode: OpenSSL::SSL::VERIFY_NONE},
			port: 993
		)
    @imap.login(@config[:imap][:login], @config[:imap][:password])
    #@imap.select(SOURCE_MAILBOX)
	end

	def disconnect!
    imap.logout
    imap.disconnect
	end

	def examine_message message
    m = Mail.read_from_string message.attr[@saved_key]
		return if m.from.nil?
		return if m.to.nil?

		body_emails = extract_body_mail m.body.parts

    ## Create association between extracted addreses and email part
		mail_struct = { 
			from: [m.from || []].flatten.reject{|e| e.nil?},
			to:   [m.to || []].flatten.reject{|e| e.nil?},
			cc:   [m.cc || []].flatten.reject{|e| e.nil?},
			body: (body_emails.to_a || []).reject{|e| e.nil?}
		}
		#pp m
		#pp mail_struct
		emails = Set.new
		mail_struct.each {|key, val|  emails.merge val }
		remaining_emails = emails.reject{|e| @contact_manager.include?(e) }

		# Skip examination of no addresses are remaining
		if remaining_emails.empty? then
			return
		end

		display_header mail_struct, remaining_emails

		while true
			begin
				puts "\n### #{m.subject}"
				print "#{mail_struct[:from].join(',')} --> #{mail_struct[:to].join(',')} "
				puts "[Ignore/Add/Skip/Detail] ?"

				i = STDIN.gets 
				case i.strip
				when /^[iI]$/ then # ignore
					@contact_manager.ignore_contact remaining_emails
					break
				when /^[aA]$/ then # add
					@contact_manager.keep_contact remaining_emails
					break
				when /^[sS]$/ then #skip
					break
				when /^[dD]$/ then # decode
					# puts m.body.decoded
					File.open(TMPMAIL_FILE + ".2", 'w') do |f| 
						f.write message.attr[@saved_key]
					end
					system "formail < #{TMPMAIL_FILE}.2 > #{TMPMAIL_FILE}"
					system "mutt -R -f #{TMPMAIL_FILE}"
				end
			rescue Encoding::ConverterNotFoundError
				STDERR.puts "ERROR: encoding problem in email. Unable to convert."
			end
		end

		return
	end

	def examine_all
    @imap.list('', '*').each do |mailbox|
			puts "\nMAILBOX #{mailbox.name}".yellow
			next unless mailbox.name =~ /#{@config[:imap][:pattern]}/
      @imap.examine mailbox.name

      puts "Searching #{mailbox.name}"
      messages_in_mailbox = @imap.responses['EXISTS'][0]
      if not messages_in_mailbox then
        say "#{mailbox.name} does not have any messages"
				next
      end

      @imap.select mailbox.name #GYR: TEST
      ids = @imap.search('SINCE 1-Jan-2001')
			# NOT OR TO "@agilefant.org" CC "@agilefant.org"')
      if ids.empty?
        puts "\tFound no messages"
			else
				examine_message_list mailbox.name, ids
      end
    end
	end

	def examine_message_list mailbox_name, ids
	  progressbar = ProgressBar.create(:total => ids.size)

    ids.each do |id|
      @imap.select mailbox_name #GYR: TEST
			message = imap.fetch(id, [@saved_key])[0]
			examine_message message
			progressbar.increment
    end 
	rescue IOError
		# re-connect and try again
		connect!
		retry
	end

  def extract_body_mail body_parts
		body_emails = Set.new
		body_parts.each do |part|
			next if part.content_type != 'text/plain'

			part_emails = part.decoded.scan MAIL_REGEXP
			if not part_emails.empty? then
				body_emails.merge part_emails
			end
		end
		body_emails
  end

  def display_header header_struct, remaining_emails
		puts ""
		header_struct.each do |key, list|
			#pp list
			list.each do |addr|
				addr_str = if remaining_emails.include? addr then
								   	 addr.yellow.on_black
							   	 else addr
							   	 end
				str = "%4s: %s" % [key.to_s.upcase, addr_str]
				puts str
			end
		end
		puts ""
  end
end
