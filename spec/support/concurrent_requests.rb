# Shared setup for examples that send requests to the app from several threads at once.
RSpec.shared_context 'with concurrent requests' do
  # The requests run on connections of their own, so they cannot see the data of a test transaction.
  self.use_transactional_tests = false

  after do
    Loan.delete_all
    Reader.delete_all
    Book.delete_all
  end

  # Sends a request to the app on a database connection of its own. `json` becomes the request body.
  def app_request(method, path, json: nil)
    ActiveRecord::Base.connection_pool.with_connection do
      env = json ? { 'CONTENT_TYPE' => 'application/json', input: json.to_json } : {}
      Rack::MockRequest.new(Rails.application).public_send(method, path, env)
    end
  end

  # Sends the request from a new thread; the value of the thread is the response.
  def request_in_thread(method, path, json: nil)
    Thread.new { app_request(method, path, json:) }
  end

  # Calls `subscriber` for every SQL statement while the block runs.
  def watching_sql(subscriber)
    handle = ActiveSupport::Notifications.subscribe('sql.active_record', subscriber)
    yield
  ensure
    ActiveSupport::Notifications.unsubscribe(handle)
  end

  # Makes every request wait at its first SQL statement matching `pattern` until `requests` of them have reached it,
  # either just before the statement runs (`at: :start`) or right after it ran (`at: :finish`).
  def line_up_at_sql(pattern, requests:, at:, &)
    barrier = Concurrent::CyclicBarrier.new(requests)
    arrive = ->(payload) { barrier.wait(5) if payload[:sql].match?(pattern) }
    subscriber =
      if at == :start
        Class.new do
          define_method(:start) { |_name, _id, payload| arrive.call(payload) }
          def finish(*); end
        end.new
      else
        ->(*, payload) { arrive.call(payload) }
      end
    watching_sql(subscriber, &)
  end
end
