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
  config_param :insert_columns, :string, :default => nil
  config_param :columns, :string, :default => nil
  config_param :insert_values, :string, :default => nil
  config_param :values, :string, :default => nil
  config_param :unique_column, :string, :default => nil

  config_param :sequence_moniker, :string, :default => nil

  config_param :file_moniker, :string, :default => nil
  config_param :file_record_filter, :string, :default => nil
  config_param :file_format, :string, :default=> nil
  config_param :file_write_limit, :integer, :default=>10000
  config_param :sequence_column, :string, :default => "seq"

  attr_accessor :handler

  def client
    PG::Connection.new({
      :host => @host, :port => @port,
      :user => @username, :password => @password,
      :dbname => @database
    })
  end

  def configure(conf)
    super

    @insert_columns ||= @columns
    @insert_values ||= @values

    if @insert_columns.nil?
      raise fluent::configerror, "columns must be specified, but missing"
    end

    @table_moniker_lambda = eval("lambda#{@table_moniker}")
    @insert_filter_lambda = eval("lambda#{@insert_filter}")
    if @file_moniker
      @file_moniker_lambda = eval("lambda#{@file_moniker}")
      @sequence_moniker ||= '{|table|"/tmp/#{table}.seq"}'
      case @file_format
      when "json" || "msgpack" || "message_pack"
        @file_record_filter ||= '{|record|record}'
      when "ltsv"
        @file_record_filter ||= '{|fields,record|[fields,record]}'
      else
      end
    end
    @file_record_filter_lambda = eval("lambda#{@file_record_filter}") if @file_record_filter
    @sequence_moniker_lambda = eval("lambda#{@sequence_moniker}") if @sequence_moniker
    self
  end

  DB_ESCAPE_PATTERN = Regexp.new("[\\\\\\a\\b\\n\\r\\t]")

  def db_escape(str)
    return "\\N" if str.nil?
    rest = str
    ret = ''
    while match_data = DB_ESCAPE_PATTERN.match(rest)
      ret += match_data.pre_match
      code = match_data[0]
      rest = match_data.post_match
      case code
      when '\\'
        ret += '\\\\'
      when "\a"
        ret += "\\a"
      when "\b"
        ret += "\\b"
      when "\n"
        ret += "\\n"
      when "\r"
        ret += "\\r"
      when "\t"
        ret += "\\t"
      end
    end
    return ret + rest
  end

  def delete_duplicative_records(records)
    records.uniq!{|r|r[@unique_column]}
  end

  def delete_existing_records(handler, table, records)
    unique_values = records.map{|r|r[@unique_column]}
    if unique_values != []
      where_sql = "where " + 1.upto(unique_values.size).map{|i|"#{@unique_column} = \$#{i}"}.join(" or ")
      handler.prepare("select_#{table}", "select #{@unique_column} from #{table} #{where_sql}")
      result = handler.exec_prepared("select_#{table}", unique_values)
      exist_values = result.column_values(0)
      return if exist_values.size == 0
      $log.info "delete #{exist_values.size} duplicative records for #{table}"
      records.reject!{|r|exist_values.include?(r[@unique_column])}
    end
  end

  def file_path(table)
    @file_moniker_lambda.call(table)
  end

  def filter_for_file_record(*args)
    result = @file_record_filter_lambda.call(*args)
    return result
  end

  def filter_for_insert(record)
    @insert_filter_lambda.call(record)
  end

  def sequence_path(table)
    @sequence_moniker_lambda.call(table)
  end

  def format(tag, time, record)
    [tag, time, record].to_msgpack
  end

  def initialize
    super
    require 'pg'
  end

  def insert_into_db(handler, table, records)
    if @unique_column
      delete_duplicative_records(records)
      delete_existing_records(handler, table, records)
    end

    $log.info "insert #{records.size} records into #{table}"
    sql = "INSERT INTO #{table}(#{@insert_columns}) VALUES(#{@insert_values})"
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

  def read_last_sequence(filepath)
    last_sequence =  File.read(filepath).chomp
    last_sequence = nil if /-?[0-9]+/ !~ last_sequence
    return last_sequence
  end

  def read_last_sequence_from_file(handler, table, filepath)
    last_line = `tail -n 1 #{filepath}`
    case @file_format
    when "json"
      last_record = JSON.parse(last_line)
      last_sequence = last_record[@sequence_column]
    when "ltsv"
      last_record = Hash[last_line.split(/\t/).map{|p|p.split(/:/, 2)}]
      last_sequence = last_record[@sequence_column]
    else
      result = handler.exec("select * from #{table} limit 0")
      fields = result.fields
      sequence_index = fields.index(@sequence_column)
      last_record = last_line.split(/\t/)
      last_sequence = last_record[sequence_index]
    end
    last_sequence = nil if /-?[0-9]+/ !~ last_sequence
    return last_sequence
  end

  def shutdown
    super
  end

  def start
    super
  end

  def table_name(record)
    @table_moniker_lambda.call(record)
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
      insert_into_db(handler, table, records)
      write_to_file(handler, table) if @file_moniker
    end
    handler.close
  end

  def write_pg_result(output_stream, fields, pg_result)
    case @file_format
    when "json"
      pg_result.each do |tuple|
        tuple = filter_for_file_record(tuple)
        output_stream.puts(tuple.to_json)
      end
    when "ltsv"
      pg_result.each_row do |row|
        fields, row = filter_for_file_record(fields, row)
        output_stream.puts(fields.each_with_index.map{|f,i|"#{f}:#{db_escape(row[i])}"}.join("\t"))
      end
    when "msgpack" || "message_pack"
      pg_result.each do |tuple|
        tuple = filter_for_file_record(tuple)
        output_stream.write(tuple.to_msgpack)
      end
    else
      pg_result.each_row do |row|
        output_stream.puts(row.map{|v|db_escape(v)}.join("\t"))
      end
    end
  end

  def write_to_file(handler, table)
    sequence_file_path = sequence_path(table)
    last_sequence = read_last_sequence(sequence_file_path) if File.exists?(sequence_file_path)
    file = nil
    while true
      where_sql = "where #{last_sequence} < #{@sequence_column}" if last_sequence
      result = handler.exec("select * from #{table} #{where_sql} order by #{@sequence_column} limit #{@file_write_limit}")
      result_size = result.ntuples
      break if result_size == 0

      fields ||= result.fields
      file ||= File.open(file_path(table), "a")
      write_pg_result(file, fields, result)
      last_sequence = result[result_size-1][@sequence_column]
      break if result_size < @file_write_limit
    end
    if file
      file.close
      File.write(sequence_file_path, last_sequence.to_s) if last_sequence
    end
  end
end
