require "spec_helper"

describe Fluent::PgdistOutput do
  def init_test_tables
    sql = %[
      CREATE SCHEMA pgdist;
      DROP TABLE pgdist.pgdist_test20130430;
      DROP TABLE pgdist.pgdist_test20130501;
      CREATE TABLE pgdist.pgdist_test20130430(
        seq serial NOT NULL,
        id text unique,
        created_at timestamp without time zone,
        value text);
      CREATE TABLE pgdist.pgdist_test20130501(
        seq serial NOT NULL,
        id text unique,
        created_at timestamp without time zone,
        value text);
      INSERT INTO pgdist.pgdist_test20130501(id, created_at, value)
      VALUES ('101', '2013-05-01T01:23:45Z', 'dummy');
    ]
    `echo "#{sql}" | psql -U postgres -d pgdist 2>/dev/null`
    exist_record = [1, '101','2013-05-01T01:23:45Z','dummy']
    `rm /tmp/pgdist.pgdist_test20130430 2>/dev/null`
    File.write("/tmp/pgdist.pgdist_test20130501", exist_record.join("\t") + "\n")
    `rm /tmp/pgdist.pgdist_test20130430.seq 2>/dev/null`
    File.write("/tmp/pgdist.pgdist_test20130501.seq", "1")
  end

  before :all do 
    Fluent::Test.setup
    @input_records = [
      {'id'=>'100','created_at'=>'2013-04-30T01:23:45Z','text'=>'message1'},
      {'id'=>'101','created_at'=>'2013-05-01T01:23:45Z','text'=>'message2'},
      {'id'=>'101','created_at'=>'2013-05-01T01:23:45Z','text'=>'message2'},
      {'id'=>'102','created_at'=>'2013-05-01T01:23:46Z','text'=>'message3'}
    ]
    tag = "pgdist.test"
    @default_conf = %[
host localhost 
username postgres
password postgres
database pgdist
table_moniker {|record|t=record["created_at"];"pgdist.pgdist_test"+t[0..3]+t[5..6]+t[8..9]}
insert_filter {|record|[record["id"],record["created_at"],record.to_json]}
columns id,created_at,value
values $1,$2,$3
file_moniker {|table|"/tmp/"+table}
    ]
    @driver = Fluent::Test::BufferedOutputTestDriver.new(Fluent::PgdistOutput, "pgdist.test").configure(@default_conf)
    unique_conf = @default_conf + "unique_column id\n"
    @unique_driver = Fluent::Test::BufferedOutputTestDriver.new(Fluent::PgdistOutput, "pgdist.test").configure(unique_conf)
    @connection = PG::Connection.new({
      :host => "localhost", :port => 5432,
      :user => "postgres", :password => "postgres",
      :dbname => "pgdist"
    })
  end

  after :all do
    @connection.close
  end

  describe "#db_escape(str)" do
    context "when str = nil" do
      it "should return \\N" do
        @driver.instance.db_escape(nil).should == "\\N"
      end
    end

    context "when str = #{"\\1\a2\b3\n4\r5\t6\\\a\b\n\r\t".inspect}" do
      it "should return #{"\\\\1\\a2\\b3\\n4\\r5\\t6\\\\\\a\\b\\n\\r\\t".inspect}" do
        input = "\\1\a2\b3\n4\r5\t6\\\a\b\n\r\t"
        expected = "\\\\1\\a2\\b3\\n4\\r5\\t6\\\\\\a\\b\\n\\r\\t"
        @driver.instance.db_escape(input).should == expected
      end
    end
  end

  describe "#delete_existing_records(handler, table, record)" do
    before :each do
      init_test_tables
    end

    it "should delete existing records" do
      handler = @unique_driver.instance.client
      records = @input_records[1..3]
      @unique_driver.instance.delete_existing_records(handler, "pgdist.pgdist_test20130501", records)
      records.shift.should == {"id"=>"102", "created_at"=>"2013-05-01T01:23:46Z", "text"=>"message3"}
      records.size.should == 0
    end
  end

  describe "#filter_for_insert(record)" do
    context "when record is valid Hash" do
      it "should output valid Array" do
        result = @driver.instance.filter_for_insert(@input_records[0])
        result.shift.should == "100"
        result.shift.should == "2013-04-30T01:23:45Z"
        json = result.shift
        hash = JSON.parse(json)
        hash["id"].should == "100"
        hash["created_at"].should == "2013-04-30T01:23:45Z"
        hash["text"].should == "message1"
      end
    end
  end

  describe "#format(tag, time, record)" do
    it "should output in valid format" do
      records = @input_records
      time = Time.utc(2013,4,30,1,23,45).to_i
      result = @driver.instance.format("pgdist.test", time, @input_records[0])
      result.should == ['pgdist.test', time, @input_records[0]].to_msgpack
    end
  end

  describe "#table_name(record)" do
    context "when record['created_at'] = '2013-04-30T01:23:45Z'" do
      it "should return 'pgdist.pgdist_test20130430'" do
        result = @driver.instance.table_name(@input_records[0])
        result.should == "pgdist.pgdist_test20130430"
      end
    end
  end

  describe "#write(chunk)" do
    before :all do
      time = Time.utc(2013,4,30,1,23,45).to_i
      @input_records.each do |record|
        @driver.emit(record, time)
        @unique_driver.emit(record, time)
      end
    end

    before :each do
      init_test_tables
    end

    context "when unique_column is not set" do
      it "should insert into PostgreSQL" do
        @driver.run
        result = @connection.exec("select * from pgdist.pgdist_test20130430")

        result.ntuples.should == 1

        record = result[0]
        record["seq"].should == "1"
        record["id"].should == "100"
        record["created_at"].should == "2013-04-30 01:23:45"
        json = record["value"]
        hash = JSON.parse(json)
        hash["id"].should == "100"
        hash["created_at"].should == "2013-04-30T01:23:45Z"
        hash["text"].should == "message1"

        result = @connection.exec("select * from pgdist.pgdist_test20130501")

        result.ntuples.should == 2

        record = result[0]
        record["seq"].should == "1"
        record["id"].should == "101"
        record["created_at"].should == "2013-05-01 01:23:45"
        record["value"].should == "dummy"

        record = result[1]
        record["seq"].should == "4"
        record["id"].should == "102"
        record["created_at"].should == "2013-05-01 01:23:46"
        json = record["value"]
        hash = JSON.parse(json)
        hash["id"].should == "102"
        hash["created_at"].should == "2013-05-01T01:23:46Z"
        hash["text"].should == "message3"
      end

      it "should append to file" do
        @driver.run

        result = File.read("/tmp/pgdist.pgdist_test20130430.seq").chomp
        result.should == "1"

        result = File.read("/tmp/pgdist.pgdist_test20130430").split(/\n/).map{|l|l.split(/\t/)}
        result.shift.should == ["1", "100", "2013-04-30 01:23:45", "{\"id\":\"100\",\"created_at\":\"2013-04-30T01:23:45Z\",\"text\":\"message1\"}"]
        result.size.should == 0

        result = File.read("/tmp/pgdist.pgdist_test20130501.seq").chomp
        result.should == "4"

        result = File.read("/tmp/pgdist.pgdist_test20130501").split(/\n/).map{|l|l.split(/\t/)}
        result.shift.should == ["1", "101", "2013-05-01T01:23:45Z", "dummy"]
        result.shift.should == ["4", "102", "2013-05-01 01:23:46", "{\"id\":\"102\",\"created_at\":\"2013-05-01T01:23:46Z\",\"text\":\"message3\"}"]
        result.size.should == 0
      end
    end

    context "when unique_column is set" do
      it "should insert into PostgreSQL" do
        @unique_driver.run
        result = @connection.exec("select * from pgdist.pgdist_test20130430")

        result.ntuples.should == 1

        record = result[0]
        record["seq"].should == "1"
        record["id"].should == "100"
        record["created_at"].should == "2013-04-30 01:23:45"
        json = record["value"]
        hash = JSON.parse(json)
        hash["id"].should == "100"
        hash["created_at"].should == "2013-04-30T01:23:45Z"
        hash["text"].should == "message1"

        result = @connection.exec("select * from pgdist.pgdist_test20130501")

        result.ntuples.should == 2

        record = result[0]
        record["seq"].should == "1"
        record["id"].should == "101"
        record["created_at"].should == "2013-05-01 01:23:45"
        record["value"].should == "dummy"

        record = result[1]
        record["seq"].should == "2"
        record["id"].should == "102"
        record["created_at"].should == "2013-05-01 01:23:46"
        json = record["value"]
        hash = JSON.parse(json)
        hash["id"].should == "102"
        hash["created_at"].should == "2013-05-01T01:23:46Z"
        hash["text"].should == "message3"
      end

      it "should append to file" do
        @unique_driver.run

        result = File.read("/tmp/pgdist.pgdist_test20130430.seq").chomp
        result.should == "1"

        result = File.read("/tmp/pgdist.pgdist_test20130430").split(/\n/).map{|l|l.split(/\t/)}
        result.shift.should == ["1", "100", "2013-04-30 01:23:45", "{\"id\":\"100\",\"created_at\":\"2013-04-30T01:23:45Z\",\"text\":\"message1\"}"]
        result.size.should == 0

        result = File.read("/tmp/pgdist.pgdist_test20130501.seq").chomp
        result.should == "2"

        result = File.read("/tmp/pgdist.pgdist_test20130501").split(/\n/).map{|l|l.split(/\t/)}

        result.shift.should == ["1", "101", "2013-05-01T01:23:45Z", "dummy"]
        result.shift.should == ["2", "102", "2013-05-01 01:23:46", "{\"id\":\"102\",\"created_at\":\"2013-05-01T01:23:46Z\",\"text\":\"message3\"}"]
        result.size.should == 0
      end
    end
  end

  describe "#write_pg_result(output_stream, file_fields, pg_result)" do
    before :all do
      @pg_result = @connection.exec(%[
        (select 1 as seq, '100' as id, E'test\\ndata1' as value)
        union
        (select 2 as seq, '101' as id, E'test\\ndata2' as value)
      ])
    end

    after :all do
    end

    before :each do
      pipe = IO.pipe
      @output_reader = pipe[0]
      @output_writer = pipe[1]
    end

    after :each do
      @output_reader.close unless @output_reader.closed?
      @output_writer.close unless @output_writer.closed?
    end

    context "when file_format = json" do
      before :each do
        json_conf = @default_conf + %[
          file_format json
          file_record_filter {|r|{"seq"=>r["seq"],"id"=>r["id"],"text"=>r["value"]}}
        ]
        @json_driver = Fluent::Test::BufferedOutputTestDriver.new(Fluent::PgdistOutput, "pgdist.test").configure(json_conf)
      end

      it "should output json data" do
        @json_driver.instance.write_pg_result(@output_writer, ["seq", "id", "value"], @pg_result)
        @output_writer.close
        result = @output_reader.gets.chomp
        result = JSON.parse(result)
        result.should == {"seq"=>"1", "id"=>"100", "text"=>"test\ndata1"}
        result = @output_reader.gets.chomp
        result = JSON.parse(result)
        result.should == {"seq"=>"2", "id"=>"101", "text"=>"test\ndata2"}
      end
    end

    context "when file_format = ltsv" do
      before :each do
        ltsv_conf = @default_conf + %[
          file_format ltsv
          file_record_filter {|f,r|[["seq","id","text"],[r[0],r[1],r[2]]]}
        ]
        @ltsv_driver = Fluent::Test::BufferedOutputTestDriver.new(Fluent::PgdistOutput, "pgdist.test").configure(ltsv_conf)
      end

      it "should output ltsv data" do
        @ltsv_driver.instance.write_pg_result(@output_writer, ["seq", "id", "value"], @pg_result)
        @output_writer.close
        result = @output_reader.gets.chomp
        result = Hash[result.split(/\t/).map{|p|p.split(/:/, 2)}]
        result.should == {"seq"=>"1", "id"=>"100", "text"=>"test\\ndata1"}
        result = @output_reader.gets.chomp
        result = Hash[result.split(/\t/).map{|p|p.split(/:/, 2)}]
        result.should == {"seq"=>"2", "id"=>"101", "text"=>"test\\ndata2"}
        @output_reader.gets.should be_nil
      end
    end

    context "when file_format = msgpack" do
      before :each do
        msgpack_conf = @default_conf + %[
          file_format msgpack
          file_record_filter {|r|{"seq"=>r["seq"],"id"=>r["id"],"text"=>r["value"]}}
        ]
        @msgpack_driver = Fluent::Test::BufferedOutputTestDriver.new(Fluent::PgdistOutput, "pgdist.test").configure(msgpack_conf)
      end

      it "should output message_pack data" do
        @msgpack_driver.instance.write_pg_result(@output_writer, ["seq", "id", "value"], @pg_result)
        @output_writer.close
        unpacker = MessagePack::Unpacker.new(@output_reader)
        result = []
        begin
          unpacker.each do |record|
            result.push record
          end
        rescue EOFError => e
        end
        result.shift.should == {"seq"=>"1", "id"=>"100", "text"=>"test\ndata1"}
        result.shift.should == {"seq"=>"2", "id"=>"101", "text"=>"test\ndata2"}
      end
    end

    context "when file_format = raw" do
      before :each do
        tsv_conf = @default_conf + "file_format raw\n"
        @tsv_driver = Fluent::Test::BufferedOutputTestDriver.new(Fluent::PgdistOutput, "pgdist.test").configure(tsv_conf)
      end
      it "should output tsv data" do
        @tsv_driver.instance.write_pg_result(@output_writer, ["seq", "id", "value"], @pg_result)
        @output_writer.close
        result = @output_reader.gets.chomp
        result = result.split(/\t/)
        result.should == ["1", "100", "test\\ndata1"]
        result = @output_reader.gets.chomp
        result = result.split(/\t/)
        result.should == ["2", "101", "test\\ndata2"]
        @output_reader.gets.should be_nil
      end
    end
  end
end
