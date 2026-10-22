# Action Mailer delivery method for an app that never really sends email: the message is written to the log instead.
class LogDelivery
  def initialize(_settings); end

  def deliver!(mail)
    Rails.logger.info(<<~LOG)
      Email not sent, logged instead
      From: #{mail[:from]}
      To: #{mail[:to]}
      Subject: #{mail.subject}

      #{mail.body.decoded}
    LOG
  end
end
