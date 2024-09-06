## Adding Solid Queue

To schedule the `Litestream::VerificationJob` to run at regular intervals and also to generally be able to run background jobs for our application, we can use the [Solid Queue gem](https://github.com/rails/solid_queue). Solid Queue is a DB-based queuing backend for Active Job, designed with simplicity and performance in mind. And it works great with SQLite.

### The Implementation

Adding the gem is straight-forward:

```sh
bundle add solid_queue
```

Because Solid Queue is constantly polling the database and making frequent updates, it is recommended to use a separate database for the queue when using Solid Queue with SQLite. This will prevent the queue from interfering with the main database and vice versa. To do this, we can create a new SQLite database for the queue. In the `config/database.yml` file, we can add a new configuration for the queue:

```yaml
queue: &queue
  <<: *default
  migrations_paths: db/queue_migrate
  database: storage/<%= Rails.env %>-queue.sqlite3
```

This configuration sets up a new database that will have a separate schema and separate migrations.

However, adding a new database configuration is not sufficient. We also need to ensure that every environment that needs this new `queue` database uses it alongside our primary database. As [the Rails Guides](https://guides.rubyonrails.org/active_record_multiple_databases.html) say, we need to "change our database.yml from a 2-tier to a 3-tier config."

This means that we need to define each of our databases and then specify which database each environment should use. The convention is to call the database that backs our application `primary` and the database that backs our queue `queue`. For now, we only need to ensure that the `production` environment is configured to use both.

We need to update our `production` environment configuration to look like:

```yaml
production:
  primary:
    <<: *default
    database: storage/production.sqlite3
  queue: *queue
```

With our databases configured, we can now run the Solid Queue installer, but we need to tell the installer to use the `queue` database. We can do this by setting the `DATABASE` environment variable:

```sh
RAILS_ENV=production bin/rails solid_queue:install
```

This command will create the necessary files for Solid Queue to work with the `queue` database in the `db/queue_migrate` directory. You should see output something like this:

```
      create  config/solid_queue.yml
      create  db/queue_schema.rb
      create  bin/jobs
        gsub  config/environments/production.rb
```

Now, we need to run the migrations for the `queue` database:

```sh
RAILS_ENV=production bin/rails db:prepare DATABASE=queue
```

With our `storage/production-queue.sqlite3` database prepared, we now need to tell Rails to use Solid Queue as the Active Job backend and then tell Solid Queue to use the `queue` database.

The installation generator should have added the configuration to the `config/environments/production.rb` file as well as the database connection configuration. You should see something like:

```ruby
config.active_job.queue_adapter = :solid_queue
config.solid_queue.connects_to = { database: { writing: :queue } }
```

With all of that in place, we should be able to start the Solid Queue process successfully:

```sh
RAILS_ENV=production bin/jobs
```

and see something like:

```
[SolidQueue] Starting Dispatcher(pid=48982, hostname=local, metadata={:polling_interval=>1, :batch_size=>500, :concurrency_maintenance_interval=>600, :recurring_schedule=>nil})
[SolidQueue] Starting Worker(pid=48983, hostname=local, metadata={:polling_interval=>0.1, :queues=>"*", :thread_pool_size=>3})
```

Like our Litestream replication process, we need to ensure that the Solid Queue supervisor process is running alongside our Rails application. Luckily, also like the Litestream gem, Solid Queue provides a Puma plugin as well. We can add the Solid Queue Puma plugin to our `config/puma.rb` file right below our Litestream plugin:

```ruby
# Allow puma to manage Solid Queue's supervisor process
plugin :solid_queue
```

### Scheduling the `Litestream::VerificationJob`

With Solid Queue now fully integrated into our application, we can schedule the `Litestream::VerificationJob` to run at regular intervals. We can do this by defining a recurring task in the `config/solid_queue.yml` file. By default, this file is commented out, so we need to uncomment it and add our recurring task. As detailed in the [Solid Queue documentation](https://github.com/rails/solid_queue?tab=readme-ov-file#recurring-tasks), we add recurring tasks under the `dispatchers` key in the configuration file. We need to add a task to run the `Litestream::VerificationJob` every day at 1am, so let's replace the `my_periodic_job` task with the `periodic_litestream_backup_verfication_job` task:

```yaml
default: &default
  dispatchers:
    - polling_interval: 1
      batch_size: 500
      recurring_tasks:
        periodic_litestream_backup_verfication_job:
          class: Litestream::VerificationJob
          args: []
          schedule: every day at 1am EST
```

We can verify that the recurring task is scheduled by restarting the Solid Queue process and checking the logs:

```sh
RAILS_ENV=production bin/rails solid_queue:start
```

should now output something like:

```
[SolidQueue] Starting Dispatcher(pid=55226, hostname=local, metadata={:polling_interval=>1, :batch_size=>500, :concurrency_maintenance_interval=>600, :recurring_schedule=>{:periodic_litestream_backup_verfication_job=>{:schedule=>"every day at 1am EST", :class_name=>"Litestream::VerificationJob", :arguments=>[]}}})
[SolidQueue] Starting Worker(pid=55227, hostname=local, metadata={:polling_interval=>0.1, :queues=>"*", :thread_pool_size=>3})
```

If you see the `periodic_litestream_backup_verfication_job` in the Dispatcher configuration, then the recurring task is scheduled correctly!

### The Web Dashboard

The final detail we need is a web interface to monitor the Solid Queue process. Solid Queue provides a web interface that we can mount in our Rails application. We can do this by adding Rails' new [`mission_control-jobs` gem](https://github.com/rails/mission_control-jobs):

```sh
bundle add mission_control-jobs
```

With the gem installed, we simply need to mount the engine in our `config/routes.rb` file, and let's be sure to mount it _within_ our `AuthenticatedConstraint` block to only allow authenticated users to access the interface:

```ruby
mount MissionControl::Jobs::Engine, at: "/jobs"
```

Of course, in a real-world application, you would want to ensure that only specifically authorized users can access the Solid Queue web interface. You could do this by creating a new constraint and wrapping the `mount` call in that constraint.

In order to confirm that the engine is mounted and accessible, we need to (re)start our Rails server. But, before we do that, we will need to recompile our assets in production in order to get Mission Control's assets added to our application:

```sh
RAILS_ENV=production bin/rails assets:precompile
```

Once that is complete, restart the Rails server:

```sh
bin/serve
```

Ensure that you are logged in as a user (reminder, all seeded users share the `password` password), and navigate to `http://localhost:3000/jobs`. You should see the Solid Queue web interface, which will allow you to monitor the Solid Queue process and view the status of your jobs.

### Conclusion

In this step, we have integrated Solid Queue, backed by a separate SQLite database, into our application. We have also added the web dashboard for managing background jobs. And building on the last step, we have scheduled the Litestream verification job to run daily. With these changes, we have a robust system for managing background jobs and ensuring the integrity of our database backups.
