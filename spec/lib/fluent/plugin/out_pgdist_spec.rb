require "spec_helper"

describe Fluent::PgdistOutput do
  before :all do 
    Fluent::Test.setup
    @input_records = [
      {'id'=>'100','created_at'=>'2013-04-30T01:23:45Z','text'=>'message1'},
      {'id'=>'101','created_at'=>'2013-05-01T01:23:45Z','text'=>'message2'},
      {'id'=>'101','created_at'=>'2013-05-01T01:23:45Z','text'=>'message2'}
    ]
    conf = %[
host localhost 
username postgres
password postgres
database pgdist
table_moniker {|record|t=record["created_at"];"pgdist.pgdist_test"+t[0..3]+t[5..6]+t[8..9]}
insert_filter {|record|[record["id"],record["created_at"],record.to_json]}
columns id,created_at,value
values $1,$2,$3
    ]
    tag = "pgdist.test"
    @driver = Fluent::Test::BufferedOutputTestDriver.new(Fluent::PgdistOutput, tag).configure(conf)
  end

  describe "#table_name(record)" do
    context "when record['created_at'] = '2013-04-30T01:23:45Z'" do
      it "should return 'pgdist.pgdist_test20130430'" do
        result = @driver.instance.table_name(@input_records[0])
        result.should == "pgdist.pgdist_test20130430"
      end
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

  describe "#write(chunk)" do
    before :all do
      @connection = PG::Connection.new({
        :host => "localhost", :port => 5432,
        :user => "postgres", :password => "postgres",
        :dbname => "pgdist" 
      })
      sql = <<-EOF
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
      EOF
      `echo "#{sql}" | psql -U postgres -d pgdist 2>/dev/null`
    end

    it "should insert into PostgreSQL" do
      records = @input_records
      time = Time.utc(2013,4,30,1,23,45).to_i
      records.each do |record|
        @driver.emit(record, time)
      end
      @driver.run
      result = @connection.exec("select * from pgdist.pgdist_test20130430")

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

      record = result[0]
      record["seq"].should == "1"
      record["id"].should == "101"
      record["created_at"].should == "2013-05-01 01:23:45"
      json = record["value"]
      hash = JSON.parse(json)
      hash["id"].should == "101"
      hash["created_at"].should == "2013-05-01T01:23:45Z"
      hash["text"].should == "message2"

      @connection.close
    end
  end
end

