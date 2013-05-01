# fluent-plugin-pgdist

fluent-plugin-pgdist is a fluentd plugin for distribute insert into PostgreSQL.

## Install

    # gem install fluentd
    # gem install fluent-plugin-pgdist

## Usage

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
     100 | 2013-05-01 01:23:45 | {"id":"101","created_at":"2013-05-01T01:23:45Z","text":"message2"}
    (1 行)

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
