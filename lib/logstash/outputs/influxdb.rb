# encoding: utf-8
require "logstash/namespace"
require "logstash/outputs/base"
require "stud/buffer"

# This output lets you output Metrics to InfluxDB
#
# The configuration here attempts to be as friendly as possible
# and minimize the need for multiple definitions to write to
# multiple series and still be efficient
#
# the InfluxDB API let's you do some semblance of bulk operation
# per http call but each call is database-specific
#
# You can learn more at http://influxdb.com[InfluxDB homepage]
class LogStash::Outputs::InfluxDB < LogStash::Outputs::Base
  include Stud::Buffer

  config_name "influxdb"
  milestone 1

  # The database to write
  config :database, validate: :string, default: "stats"

  # The hostname or IP address to reach your InfluxDB instance
  config :host, validate: :string, required: true

  # The port for InfluxDB
  config :port, validate: :number, default: 8086

  # The user who has access to the named database
  config :username, validate: :string, default: nil, required: true

  # The password for the user who access to the named database
  config :password, validate: :password, default: nil, required: true

  # Series name - supports sprintf formatting
  config :series, validate: :string, default: "logstash"

  # String name of the field containing the point to be sent to InfluxDB
  config :point_field, validate: :string, default: 'point'

  # Set the level of precision of `time`
  #
  # only useful when overriding the time value
  config :time_precision, validate: ["m", "s", "u"], default: "s"

  # This setting controls how many events will be buffered before sending a batch
  # of events. Note that these are only batched for the same series
  config :flush_size, validate: :number, default: 100

  # The amount of time since last flush before a flush is forced.
  #
  # This setting helps ensure slow event rates don't get stuck in Logstash.
  # For example, if your `flush_size` is 100, and you have received 10 events,
  # and it has been more than `idle_flush_time` seconds since the last flush,
  # logstash will flush those 10 events automatically.
  #
  # This helps keep both fast and slow log streams moving along in
  # near-real-time.
  config :idle_flush_time, validate: :number, default: 1

  public
  def register
    require "ftw"
    require 'cgi'

    @agent = FTW::Agent.new
    @queue = []

    @base_url     = "http://#{@host}:#{@port}/db/#{@database}/series"
    @query_params = "u=#{@username}&p=#{@password.value}&time_precision=#{@time_precision}"

    @url          = "#{@base_url}?#{@query_params}"
    
    buffer_initialize(
      max_items:    @flush_size,
      max_interval: @idle_flush_time,
      logger:       @logger
    )
  end # def register
  
  public
  def receive(event)
    return unless output?(event)

    # A batch POST for InfluxDB looks like this:
    # [
    #   {
    #     "name": "events",
    #     "columns": ["state", "email", "type"],
    #     "points": [
    #       ["ny", "paul@influxdb.org", "follow"],
    #       ["ny", "todd@influxdb.org", "open"]
    #     ]
    #   },
    #   {
    #     "name": "errors",
    #     "columns": ["class", "file", "user", "severity"],
    #     "points": [
    #       ["DivideByZero", "example.py", "someguy@influxdb.org", "fatal"]
    #     ]
    #   }
    # ]

    influxdb_point = event[event.sprintf(@point_field)]

    influxdb_point['time'] ||= event.timestamp.to_i

    event_hash = {
      'name'    => event['series'] || event.sprintf(@series),
      'columns' => influxdb_point.keys,
      'points'  => [influxdb_point.values]
    }

    buffer_receive(event_hash)
  end # def receive

  def flush(events, teardown=false)
    # Avoid creating a new string for newline every time
    newline = "\n".freeze

    # seen_series stores a list of series and associated columns
    # we've seen for each event
    # so that we can attempt to batch up points for a given series.
    #
    # Columns *MUST* be exactly the same
    seen_series = {}

    event_collection = []

    events.each do |event|
      begin
        if seen_series.has_key?(event['name']) and (seen_series[event['name']] == event['columns'])
          @logger.info("Existing series data found. Appending points to that series")

          event_collection.select do |h|
            h['points'] << event['points'][0] if h['name'] == event['name']
          end
        elsif seen_series.has_key?(event['name']) and (seen_series[event['name']] != event['columns'])
          @logger.warn("Series '#{event['name']}' has been seen but columns are different or in a different order. Adding to batch but not under existing series")
          @logger.warn("Existing series columns were: #{seen_series[event['name']].join(",")} and event columns were: #{event['columns'].join(",")}")

          event_collection << event
        else
          seen_series[event['name']] = event['columns']

          event_collection << event
        end
      rescue => exception
        @logger.info("Error adding event to collection", exception: exception)

        next
      end
    end

    post(event_collection.to_json)
  end # def receive_bulk

  def post(body)
    begin
      @logger.debug("Post body: #{body}")

      response = @agent.post!(@url, body: body)
    rescue EOFError
      @logger.warn("EOF while writing request or reading response header from InfluxDB",
                   host: @host,
                   port: @port)

      return # abort this flush
    end

    # Consume the body for error checking
    # This will also free up the connection for reuse.
    body = ""

    begin
      response.read_body { |chunk| body += chunk }
    rescue EOFError
      @logger.warn("EOF while reading response body from InfluxDB",
                   host: @host,
                   port: @port)

      return # abort this flush
    end

    if response.status != 200
      @logger.error("Error writing to InfluxDB",
                    response:      response,
                    response_body: body,
                    request_body:  @queue.join("\n"))

      return
    end
  end # def post

  def teardown
    buffer_flush(final: true)
  end # def teardown
end # class LogStash::Outputs::InfluxDB
