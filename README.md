# fluent-plugin-pgdist, a plugin for [Fluentd](http://fluentd.org)

fluent-plugin-pgdist is a fluentd plugin for distribute insert into PostgreSQL.

## Install

    # gem install fluentd
    # gem install fluent-plugin-pgdist

## Usage: Insert into PostgreSQL table

Define match directive for pgdist in fluentd config file(ex. fluent.conf):

    <match pgdist.input>
      type pgdist
      host localhost
      username postgres
      password postgres
      database pgdist
      table_moniker {|record|t=record["created_at"];"pgdist_test"+t[0..3]+t[5..6]+t[8..9]}
      insert_filter {|record|[record["id"],record["created_at"],record.to_json]}
      columns id,created_at,value
      values $1,$2,$3
      raise_exception false
    </match>

Run fluentd:

    $ fluentd -c fluent.conf &

Create output table:

    $ echo 'CREATE TABLE pgdist_test20130430(id text, created_at timestamp without time zone, value text);' | psql -U postgres -d pgdist
    $ echo 'CREATE TABLE pgdist_test20130501(id text, created_at timestamp without time zone, value text);' | psql -U postgres -d pgdist

Input data:

    $ echo '{"id":"100","created_at":"2013-04-30T01:23:45Z","text":"message1"}' | fluent-cat pgdist.input
    $ echo '{"id":"101","created_at":"2013-05-01T01:23:45Z","text":"message2"}' | fluent-cat pgdist.input

Check table data:

    $ echo 'select * from pgdist_test20130430' | psql -U postgres -d pgdist
     id  |     created_at      |                               value
    -----+---------------------+--------------------------------------------------------------------
     100 | 2013-04-30 01:23:45 | {"id":"100","created_at":"2013-04-30T01:23:45Z","text":"message1"}
    (1 行)
    $ echo 'select * from pgdist_test20130501' | psql -U postgres -d pgdist
     id  |     created_at      |                               value
    -----+---------------------+--------------------------------------------------------------------
     101 | 2013-05-01 01:23:45 | {"id":"101","created_at":"2013-05-01T01:23:45Z","text":"message2"}
    (1 行)

## Usage: Insert into PostgreSQL with unique constraint

Define match directive for pgdist in fluentd config file(ex. fluent.conf):

    <match pgdist.input>
      type pgdist
      host localhost
      username postgres
      password postgres
      database pgdist
      table_moniker {|record|t=record["created_at"];"pgdist_test"+t[0..3]+t[5..6]+t[8..9]}
      insert_filter {|record|[record["id"],record["created_at"],record.to_json]}
      columns id,created_at,value
      values $1,$2,$3
      raise_exception false
      unique_column id
    </match>

Run fluentd:

    $ fluentd -c fluent.conf &

Create output table:

    $ echo 'CREATE TABLE pgdist_test20130430(seq serial, id text unique, created_at timestamp without time zone, value text);' | psql -U postgres -d pgdist
    $ echo 'CREATE TABLE pgdist_test20130501(seq serial, id text unique, created_at timestamp without time zone, value text);' | psql -U postgres -d pgdist

Input data:

    $ echo '{"id":"100","created_at":"2013-04-30T01:23:45Z","text":"message1"}' | fluent-cat pgdist.input
    $ echo '{"id":"101","created_at":"2013-05-01T01:23:45Z","text":"message2"}' | fluent-cat pgdist.input
    $ echo '{"id":"101","created_at":"2013-05-01T01:23:45Z","text":"message2"}' | fluent-cat pgdist.input
    $ echo '{"id":"102","created_at":"2013-05-01T01:23:46Z","text":"message3"}' | fluent-cat pgdist.input

Check table data:

    $ echo 'select * from pgdist_test20130430' | psql -U postgres -d pgdist
     seq | id  |     created_at      |                               value
    -----+-----+---------------------+--------------------------------------------------------------------
       1 | 100 | 2013-04-30 01:23:45 | {"id":"100","created_at":"2013-04-30T01:23:45Z","text":"message1"}
    (1 行)
    $ echo 'select * from pgdist_test20130501' | psql -U postgres -d pgdist
     seq | id  |     created_at      |                               value
    -----+-----+---------------------+--------------------------------------------------------------------
       1 | 101 | 2013-05-01 01:23:45 | {"id":"101","created_at":"2013-05-01T01:23:45Z","text":"message2"}
       2 | 102 | 2013-05-01 01:23:46 | {"id":"102","created_at":"2013-05-01T01:23:45Z","text":"message3"}
    (1 行)

## Usage: Insert into PostgreSQL and LTSV file

Define match directive for pgdist in fluentd config file(ex. fluent.conf):

    <match pgdist.input>
      type pgdist
      host localhost
      username postgres
      password postgres
      database pgdist
      table_moniker {|record|t=record["created_at"];"pgdist_test"+t[0..3]+t[5..6]+t[8..9]}
      insert_filter {|record|[record["id"],record["created_at"],record.to_json]}
      columns id,created_at,value
      values $1,$2,$3
      raise_exception false
      unique_column id
      file_moniker {|table|"/tmp/"+table}
      file_format ltsv
      file_record_filter {|f,r|h=JSON.parse(r["value"]);[["seq","id","created_at","text"],[r["seq"],r["id"],r["created_at"],h["text"]]]}
      sequence_moniker {|table|"/tmp/"+table+".seq"}
      sequence_column seq
    </match>

Run fluentd:

    $ fluentd -c fluent.conf &

Create output table:

    $ echo 'CREATE TABLE pgdist_test20130430(seq serial, id text unique, created_at timestamp without time zone, value text);' | psql -U postgres -d pgdist
    $ echo 'CREATE TABLE pgdist_test20130501(seq serial, id text unique, created_at timestamp without time zone, value text);' | psql -U postgres -d pgdist

Input data:

    $ echo '{"id":"100","created_at":"2013-04-30T01:23:45Z","text":"message1"}' | fluent-cat pgdist.input
    $ echo '{"id":"101","created_at":"2013-05-01T01:23:45Z","text":"message2"}' | fluent-cat pgdist.input
    $ echo '{"id":"101","created_at":"2013-05-01T01:23:45Z","text":"message2"}' | fluent-cat pgdist.input
    $ echo '{"id":"102","created_at":"2013-05-01T01:23:46Z","text":"message3"}' | fluent-cat pgdist.input

Check table data:

    $ echo 'select * from pgdist_test20130430' | psql -U postgres -d pgdist
     seq | id  |     created_at      |                               value
    -----+-----+---------------------+--------------------------------------------------------------------
       1 | 100 | 2013-04-30 01:23:45 | {"id":"100","created_at":"2013-04-30T01:23:45Z","text":"message1"}
    (1 行)
    $ echo 'select * from pgdist_test20130501' | psql -U postgres -d pgdist
     seq | id  |     created_at      |                               value
    -----+-----+---------------------+--------------------------------------------------------------------
       1 | 101 | 2013-05-01 01:23:45 | {"id":"101","created_at":"2013-05-01T01:23:45Z","text":"message2"}
       2 | 102 | 2013-05-01 01:23:46 | {"id":"102","created_at":"2013-05-01T01:23:45Z","text":"message3"}
    (1 行)

Check file data:

    $ cat /tmp/pgdist_test20130430
    seq:1   id:100  created_at:2013-04-30 01:23:45  text:message1
    $ cat /tmp/pgdist_test20130501
    seq:1   id:101  created_at:2013-05-01 01:23:45  text:message2
    seq:2   id:102  created_at:2013-05-01 01:23:46  text:message3

## Parameter

* host
 * Database host
* port
 * Database port number
* database
 * Database name
* username
 * Database user name
* password
 * Database user password
* table_moniker
 * Ruby script that returns the table name of each record
* insert_filter
 * Ruby script that converts each record into array for insert
* columns
 * Column names in insert SQL
* values
 * Column values in insert SQL
* raise_exception
 * Flag to enable/disable exception in insert
* unique_column
 * Column name with unique constraint
* file_moniker
 * Ruby script that returns the output file name of each table
* file_format
 * Output file format. json/ltsv/msgpack/tsv format is available.
* file_record_filter
 * Ruby script to convert record for json/ltsv/msgpack file. This filter receives hash in json/msgpack format, [fields, values] in ltsv format.
* sequnece_column
 * Sequence column name in PostgreSQL table
* sequence_moniker
 * Ruby script that returns the sequence file name of each table

## Contributing to fluent-plugin-pgdist

* Check out the latest master to make sure the feature hasn't been implemented or the bug hasn't been fixed yet.
* Check out the issue tracker to make sure someone already hasn't requested it and/or contributed it.
* Fork the project.
* Start a feature/bugfix branch.
* Commit and push until you are happy with your contribution.
* Make sure to add tests for it. This is important so I don't break it in a future version unintentionally.
* Please try not to mess with the Rakefile, version, or history. If you want to have your own version, or is otherwise necessary, that is fine, but please isolate to its own commit so I can cherry-pick around it.

## Copyright

Copyright (c) 2013 haracane. See LICENSE.txt for further details.
