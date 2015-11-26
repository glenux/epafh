
class Epafh::Crawler
	attr_reader :imap
	attr_reader :contacts

	TMPMAIL_FILE = '.tmpmail'

	def initialize config
    @saved_key = 'RFC822'
    @filter_headers = 'BODY[HEADER.FIELDS (FROM TO Subject)]'.upcase
		@config = config
		@imap = nil
		@contact_manager = ContactManager.new config
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

	MAIL_REGEXP = /\b[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,4}\b/

	def examine_message message
    m = Mail.read_from_string message.attr[@saved_key]
		return if m.from.nil?
		return if m.to.nil?


		emails = Set.new
		emails.merge m.from
		emails.merge [m.to].flatten if m.to
		emails.merge [m.cc].flatten if m.cc

		body_emails = Set.new
		m.body.parts.each do |part|
			next if part.content_type != 'text/plain'

			#body_emails = m.body.decoded.scan MAIL_REGEXP
			part_emails = part.decoded.scan MAIL_REGEXP
			#pp body_emails
			if not part_emails.empty? then
				body_emails.merge part_emails
			end
		end
		emails.merge body_emails

		# puts emails.to_a.join(' , ')
		remaining_emails = (
			emails
			.map{ |e| [e, (@contact_manager.include? e)] }
			.select{ |e,t| !t }
		)
		seen_emails = (
			remaining_emails
			.empty? 
		)
		# puts @contacts.to_a.join(', ')
		if seen_emails then
			print "."
			return
		else
			puts ""
			all_addr = { 
				from: (m.from || []),
				to: (m.to || []),
				cc: (m.cc || []),
				body: (body_emails || [])
			}
			all_addr.each do |key, list|
				list.each do |addr|
					addr_str = if remaining_emails.map{|e,t| e}.include? addr then
								   	   addr.yellow.on_black
							   	   else addr
							   	   end
					str = "%4s: %s" % [key.to_s.upcase, addr_str]
					puts str
				end
			end
			puts ""
			#puts " ORIGINAL EMAILS: #{emails.to_a.join(', ')}"
			#puts "REMAINING EMAILS: #{remaining_emails.map{|e,t| e}.join(', ')}".yellow.on_black
			#puts "     SEEN EMAILS: #{seen_emails}"
		end

		while true
			begin
				puts "\n### #{m.subject}"
				print "#{m.from.join(',')} --> #{m.to.join(',')} "
				puts "[Ignore/Add/Skip/Detail] ?"

				i = STDIN.gets 
				case i.strip
				when /^[iI]$/ then # ignore
					@contact_manager.ignore_contact remaining_emails.map{|e,t| e}
					break
				when /^[aA]$/ then # add
					@contact_manager.keep_contact remaining_emails.map{|e,t| e}
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
    ids.each do |id|
      @imap.select mailbox_name #GYR: TEST
			message = imap.fetch(id, [@saved_key])[0]
			examine_message message
    end 
	rescue IOError
		# re-connect and try again
		connect!
		retry
	end

end
