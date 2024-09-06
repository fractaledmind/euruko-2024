## Restoring from a Backup

With Litestream streaming updates to your MinIO bucket, you can now restore your database from a backup. To do this, you can use the `litestream:restore` Rake task:

```sh
RAILS_ENV=production bin/rails litestream:restore -- --database=storage/production.sqlite3 -o=storage/restored.sqlite3
```

This task will download the latest snapshot and WAL files from your MinIO bucket and restore them to your local database.

When you run this task, you should see output like:

```
time=YYYY-MM-DDTHH:MM:SS.000+00:00 level=INFO msg="restoring snapshot" db=~/path/to/railsconf-2024/storage/production.sqlite3 replica=s3 generation=e9885230835eaf8b index=0 path=storage/restored.sqlite3.tmp
time=YYYY-MM-DDTHH:MM:SS.000+00:00 level=INFO msg="restoring wal files" db=~/path/to/railsconf-2024/storage/production.sqlite3 replica=s3 generation=e9885230835eaf8b index_min=0 index_max=0
time=YYYY-MM-DDTHH:MM:SS.000+00:00 level=INFO msg="downloaded wal" db=~/path/to/railsconf-2024/storage/production.sqlite3 replica=s3 generation=e9885230835eaf8b index=0 elapsed=2.622459ms
time=YYYY-MM-DDTHH:MM:SS.000+00:00 level=INFO msg="applied wal" db=~/path/to/railsconf-2024/storage/production.sqlite3 replica=s3 generation=e9885230835eaf8b index=0 elapsed=913.333µs
time=YYYY-MM-DDTHH:MM:SS.000+00:00 level=INFO msg="renaming database from temporary location" db=~/path/to/railsconf-2024/storage/production.sqlite3 replica=s3
```

You can inspect the contents of the `restored` database with the `sqlite3` console:

```sh
sqlite3 storage/restored.sqlite3
```

Check how many records are in the `posts` table:

```sql
SELECT COUNT(*) FROM posts;
```

and the same for the `comments` table:

```sql
SELECT COUNT(*) FROM comments;
```

You should see the same number of records in the `restored` database as in the `production` database.

You can close the `sqlite3` console by typing `.quit`.

### Verifying Backups

Running a single restoration like this is useful for testing, but in a real-world scenario, you would likely want to ensure that your backups are both fresh and restorable. In order to ensure that you consistently have a resilient backup strategy, the Litestream gem provides a `Litestream.verify!` method to, well, verify your backups. It is worth noting, to be clear, that this is not a feature of the underlying Litestream utility, but only a feature of the Litestream gem itself.

The method takes the path to a database file that you have configured Litestream to backup; that is, it takes one of the `path` values under the `dbs` key in your `litestream.yml` configuration file. In order to verify that the backup for that database is both restorable and fresh, the method will add a new row to that database under the `_litestream_verification` table. It will then wait 10 seconds to give the Litestream utility time to replicate that change to whatever storage providers you have configured. After that, it will download the latest backup from that storage provider and ensure that this verification row is present in the backup. If the verification row is _not_ present, the method will raise a `Litestream::VerificationFailure` exception.

Since we are using the Puma plugin, we can actually run the `Litestream.verify!` method directly from the Rails console:

```sh
RAILS_ENV=production bin/rails console
```

and run:

```ruby
Litestream.verify!("storage/production.sqlite3")
```

After 10 seconds, you will see it return `true`.

If you want to force a verification failure, you will need to comment out the Puma plugin and stop the `bin/serve` process. To confirm that the replication process is not running, check your running processes:

```sh
ps -a | grep litestream
```

If you see a process running, you can kill it with:

```sh
kill -9 <PID>
```

where `<PID>` is the process ID of the Litestream process (the first number in the set of three columns returned by the `ps` command).

Once you are sure that the replication process is not running, open the Rails console again:

```sh
RAILS_ENV=production bin/rails console
```

This time, when you run:

```ruby
Litestream.verify!("storage/production.sqlite3")
```

After 10 seconds, you will see an exception raised:

```
Verification failed for `storage/production.sqlite3` (Litestream::VerificationFailure)
```

This demonstrates that the `verify!` method truly does only report success when the verification row is present in the backup, which requires the replication process to be running smoothly.

### Automating Backup Verification

Even better than manually verifying your backups is to automate the process. In addition to the `verify!` method, the Litestream gem provides a background job to verify our backups for us. If you have an Active Job adapter that supports recurring jobs, you can configure it to run this job at regular intervals. Or, you could simply use `cron` to run the job at regular intervals. In this workshop, we will setup Solid Queue as our background job adapter in the next step. Once it is setup, we will configure this recurring job. Until then, let's explore what the job does and run it manually.

If you inspec the gem's source code, you will find that the job is implemented like so:

```ruby
module Litestream
  class VerificationJob < ActiveJob::Base
    queue_as Litestream.queue

    def perform
      Litestream::Commands.databases.each do |db_hash|
        Litestream.verify!(db_hash["path"])
      end
    end
  end
end
```

This job will allow us to verify our backup strategy for all databases we have configured Litestream to replicate. If any database fails verification, the job will raise an exception, which will be caught by Rails and logged.

All we need now is a job backend that will allow us to schedule this job to run at regular intervals.

### Conclusion

It is essential to have a backup strategy in place for your application's data. Litestream is a great tool for this purpose. In this step we have installed the gem, configured it, explored how the replication and restoration processes work, and learned how to verify our backups. With backup verification setup, the next step is to add a background job adapter.
