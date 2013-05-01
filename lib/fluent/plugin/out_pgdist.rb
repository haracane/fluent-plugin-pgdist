class Fluent::PgdistOutput < Fluent::BufferedOutput
  Fluent::Plugin.register_output('pgdist', self)

  include Fluent::SetTimeKeyMixin
  include Fluent::SetTagKeyMixin

  config_param :host, :string
  config_param :port, :integer, :default => 5432 
  config_param :database, :string
  config_param :username, :string
  config_param :password, :string, :default => ''

  config_param :table_moniker, :string, :default => nil
  config_param :insert_filter, :string, :default => nil
  config_param :raise_exception, :bool, :default => false
  config_param :columns, :string, :default => nil
  config_param :values, :string, :default => nil

  config_param :format, :string, :default => "raw" # or json

  attr_accessor :handler

  def initialize
    super
    require 'pg'
  end

  # We don't currently support mysql's analogous json format
  def configure(conf)
    super

    if @columns.nil?
      raise Fluent::ConfigError, "columns MUST be specified, but missing"
    end

    @table_moniker_lambda = eval("lambda#{@table_moniker}")
    @insert_filter_lambda = eval("lambda#{@insert_filter}")
    self
  end

  def start
    super
  end

  def shutdown
    super
  end

  def format(tag, time, record)
    [tag, time, record].to_msgpack
  end

  def client
    pgconn = PG::Connection.new({
      :host => @host, :port => @port,
      :user => @username, :password => @password,
      :dbname => @database
    })
    return pgconn
  end

  def table_name(record)
    @table_moniker_lambda.call(record)
  end

  def filter_for_insert(record)
    @insert_filter_lambda.call(record)
  end

  def write(chunk)
    handler = self.client
    records_hash = {}
    chunk.msgpack_each { |tag, time, data|
      table = @table_moniker_lambda.call(data)
      if ! table.nil?
        records_hash[table] ||= []
        records_hash[table].push data
      end
    }
    records_hash.each_pair do |table, records|
      $log.info "insert #{records.size} records into #{table}"
      sql = "INSERT INTO #{table}(#{@columns}) VALUES(#{@values})"
      $log.info "execute sql #{sql.inspect}"
      statement = "write_#{table}"
      handler.prepare(statement, sql)
      records.each do |record|
        record = filter_for_insert(record)
        $log.info "insert #{record.inspect}"
        begin
          handler.exec_prepared(statement, record)
        rescue Exception=>e
          if @raise_exception
            raise e
          else
            $log.info e.message
          end
        end
      end
    end
    handler.close
  end
end
