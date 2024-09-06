## Fixing Tail Latency

As of today, a SQLite on Rails application will struggle with concurrency. Although Rails, since version 7.1.0, ensures that your SQLite databases are running in [WAL mode](https://www.sqlite.org/wal.html), this is insufficient to ensure quality performance for web applications under concurrent load.

### The Problem

After the errored responses, the second major issue was all of the 5+ second responses. This issue is due to the nature of SQLite being an _embedded_ database. SQLite runs _within_ your Rails application's process; not in a separate process. This is a major reason why SQLite is so fast. But, in Ruby, this also means that we need to be careful to ensure that long-running SQLite IO does not block the Ruby process from handling other requests.

If that 5 seconds is ringing a bell, it is because that is precisely what our `timeout` is set to in the `default` configuration in our `database.yml` file. It seems that as our application is put under more concurrent load than the number of Puma workers it has, more and more database queries are timing out. This is our next problem to solve.

This `timeout` option in our `database.yml` configuration file will be mapped to SQLite’s [`busy_timeout` pragma](https://www.sqlite.org/pragma.html#pragma_busy_timeout).

Instead of throwing the `BUSY` exception immediately, you can tell SQLite to wait up to the `timeout` number of milliseconds. SQLite will attempt to re-acquire the write lock using a kind of exponential backoff, and if it cannot acquire the write lock within the timeout window, then and only then will the `BUSY` exception be thrown. This allows a web application to use a connection pool, with multiple connections open to the database, but not need to resolve the order of write operations itself. You can simply push queries to SQLite and allow SQLite to determine the linear order that write operations will occur in. The process will look something like this.

Imagine our application sends 4 write queries to the database at the same moment:

```
queued  |  running
-------------------
  ☐
  ☐
  ☐
  ☐
```

One of those four will acquire the write lock first and run. The other three will be queued, running the backoff re-acquire logic:

```
queued  |  running
-------------------

  ☐        ☐
  ☐
  ☐
```

Once the first write query completes, one of the queued queries will attempt to re-acquire the lock and successfully acquire the lock and start running. The other two queries will continue to stay queued and keep running the backoff re-acquire logic:

```
queued  |  running
-------------------

  ☐        ☐ ☐
  ☐

```

Again, when the second write query completes, another query will have its backoff re-acquire logic succeed and will start running. Our last query is still queued and still running its backoff re-acquire logic:

```
queued  |  running
-------------------

           ☐ ☐ ☐
  ☐

```

Once the third query completes, our final query can acquire the write lock and run:

```
queued  |  running
-------------------

           ☐ ☐ ☐ ☐


```

So long as no query is forced to wait for longer than the timeout duration, SQLite will resolve the linear order of write operations on its own. This queuing mechanism is essential to avoiding `SQLITE_BUSY` exceptions. But, there is a major performance bottleneck lurking in the details of this feature for Rails applications.

Because SQLite is embedded within your Ruby process and the thread that spawns it, care must be taken to release Ruby’s global VM lock (GVL) when the Ruby-to-SQLite bindings execute SQLite’s C code. [By design](https://github.com/sparklemotion/sqlite3-ruby/issues/287#issuecomment-615346313), the `sqlite3-ruby` gem does not release the GVL when calling SQLite. For the most part, this is a reasonable decision, but for the `busy_timeout`, it greatly hampers throughput.

Instead of allowing another Puma worker to acquire Ruby’s GVL while one Puma worker is waiting for the database query to return, that first Puma worker will continue to hold the GVL even while the Ruby operations are completely idle waiting for the database query to resolve and run. This means that concurrent Puma workers won’t even be able to send concurrent write queries to the SQLite database and SQLite’s linear writes will force our Rails app to process web requests somewhat linearly as well. This radically slows down the throughput of our Rails app.

What we want is to allow our Puma workers to be able to process requests concurrently, passing the GVL amongst themselves as they wait on I/O. So, for Rails app using SQLite, this means that we need to unlock the GVL whenever a write query gets queued and is waiting to acquire the SQLite write lock.

### The Solution

Luckily, in addition to the `busy_timeout`, SQLite also provides the lower-level [`busy_handler` hook](https://www.sqlite.org/c3ref/busy_handler.html). The `busy_timeout` is nothing more than a specific `busy_handler` implementation provided by SQLite. Any application using SQLite can provide its own custom `busy_handler`. The `sqlite3-ruby` gem is a SQLite driver, meaning that it provides Ruby bindings for the C API that SQLite exposes. Since it provides [a binding for the `sqlite3_busy_handler` C function](https://github.com/sparklemotion/sqlite3-ruby/blob/055da734dafdbb01bb8cf59dbcdb475ea822683f/ext/sqlite3/database.c#L209-L220), we can write a Ruby callback that will be called whenever a query is queued.

Here is a Ruby implementation of the logic you will find in SQLite’s C source for its `busy_timeout`. Every time this callback is called, it is passed the count of the number of times this query has called this callback. That count is used to determine how long this query should wait to try again to acquire the write lock and how long it has already waited. By using [Ruby’s `sleep`](https://docs.ruby-lang.org/en/master/Kernel.html#method-i-sleep), we can ensure that the GVL is released while a query is waiting to retry acquiring the lock.

```ruby
def busy_timeout(count)
  delays = [1, 2, 5, 10, 15, 20, 25, 25, 25, 50, 50, 100]

  if count ‹ delays.size
    delay = delays[count]
    prior = delays.take(count).sum
  else
    delay = delays.last
    prior = delays.sum + ((count - delays.size) * delay)
  end

  if prior + delay › timeout
    raise SQLite3::BusyException
  else
    sleep delay.fdiv(1000)
  end
end
```

We don't want to simply re-implement SQLite's `busy_timeout` logic in Ruby though, because this logic still has problems with long tail latency performance. This is because the backoff delay penalizes "older" queries. Because newer queries are given a shorter delay, they are more likely to acquire the write lock first. This means that the older queries will have to wait longer and longer to acquire the write lock.

So, for example, if a query has tried to acquire the write lock 4 times, it will wait to try again for 10 milliseconds. But, 10 milliseconds is longer than the sum of the previous three delays combined. So, any new query will be allowed to retry to acquire the write lock _three times_ before this query is allowed to retry _once_.

In order to prevent this penalty on some queries, which leads to increased long tail response latency, we can simply have every query retry at the same frequency. This will allow the queries to be processed in a more fair manner, and will prevent the long tail latency from increasing.

```ruby
busy_handler do |count|
  now = Process.clock_gettime (Process::CLOCK_MONOTONIC)
  if count.zero?
    @timeout_deadline = now + timeout_seconds
  elsif now › @timeout_deadline
    next false
  else
    sleep(0.001)
  end
end
```

And that is precisely [what we have done](https://github.com/sparklemotion/sqlite3-ruby/pull/456) in [version 2.0.0](https://github.com/sparklemotion/sqlite3-ruby/releases/tag/v2.0.0) of the `sqlite3-ruby` gem as the `Database#busy_handler_timeout=` method. This Ruby callback releases the GVL while waiting for a connection using the sleep operation and always sleeps 1 millisecond. These 10 lines of code make a massive difference in the performance of your SQLite on Rails application.

But, how do we make use of feature in our Rails application?

### The Implementation

As stated earlier, Rails binds the `timeout` optin the `database.yml` to the `busy_timeout` of SQLite (see [here](https://github.com/rails/rails/blob/a11f0a63673d274c59c69c2688c63ba303b86193/activerecord/lib/active_record/connection_adapters/sqlite3_adapter.rb#L781)). So, what we need to do is patch the `sqlite3-ruby` gem to have the `Database#busy_timeout(ms)` method simply delegate to the `Database#busy_handler_timeout=(ms)` method instead.

Now, this requires a monkey patch, which is not ideal. So, we will want to ensure that we do the monkey patch [responsibly](https://blog.appsignal.com/2021/08/24/responsible-monkeypatching-in-ruby.html). We will want to ensure that we only apply the patch when all of our presumptions are proven to be true; that is,

* when the `SQLite3::Database` class is defined,
* when the `SQLite3::Database#busy_timeout` method is defined and only takes one argument,
* when the `SQLite3::Database#busy_handler_timeout=` method is defined and only takes one argument, and
* when the Rails version is less than 8.0.0 (because the next major version of Rails will include this fix)

We can put this monkey patch in an initializer to ensure that it is loaded before the Rails application starts. So, let's create a new file in `config/initializers` called `sqlite3_busy_timeout_patch.rb`:

```sh
touch config/initializers/sqlite3_busy_timeout_patch.rb
```

and add the following code:

```ruby
# SQLite3::Database#busy_timeout(ms) is a method that sets the `busy_timeout` PRAGMA.
# In the context of Rails applications, this pragma causes problems, because
# the SQLite C method doesn't release Ruby's GVL, which can cause the entire
# application to hang. While the `sqlite3-ruby` gem provides an alternative
# with the `busy_handler_timeout=` method, Rails < 8.0.0 doesn't use it. Rails
# < 8.0.0 uses the `busy_timeout(ms)` method. This monkey patch replaces the
# implementation of `busy_timeout(ms)` to instead forward the call to
# `busy_handler_timeout=(ms)`. This way, the `busy_handler_timeout=(ms)` method is
# used instead of the `busy_timeout(ms)` method, which should prevent the
# application from hanging.
#
# This patch assumes the #busy_timeout=(ms) method exists on
# SQLite3::Database and accepts one argument.
#
module SQLiteBusyTimeoutMonkeypatch
  class << self
    def apply_patch
      # Rails >= 8.0.0 doesn't need this patch, since it calls the
      # `busy_handler_timeout=` method directly.
      # This patch is only necessary for Rails < 8.0.0.
      return if Rails::VERSION::MAJOR == 8

      # make sure the class we want to patch exists
      const = find_const_to_patch
      raise "Could not find class to patch" if const.nil?

      # make sure the #busy_timeout method exists and accepts one argument
      mtd = find_method_to_patch(const)
      raise "Could not find method to patch" if mtd.nil? || mtd.arity != 1

      # make sure the #busy_handler_timeout method exists and accepts one argument
      dlg = find_method_for_patch(const)
      raise "Could not find method for patch" if dlg.nil? || dlg.arity != 1

      # actually apply the patch
      const.prepend(InstanceMethods)
    end

    private

    def find_const_to_patch
      Kernel.const_get('SQLite3::Database')
    rescue NameError
      # return nil if the constant doesn't exist
    end

    def find_method_to_patch(const)
      return unless const
      const.instance_method(:busy_timeout)
    rescue NameError
      # return nil if the method doesn't exist
    end

    def find_method_for_patch(const)
      return unless const
      const.instance_method(:busy_handler_timeout=)
    rescue NameError
      # return nil if the method doesn't exist
    end
  end

  module InstanceMethods
    # forward the call to `busy_handler_timeout`
    def busy_timeout(milliseconds)
      self.busy_handler_timeout = milliseconds
    end
  end
end

SQLiteBusyTimeoutMonkeypatch.apply_patch
```

Yes, this is quite verbose, but better to be verbose, clear, and safe than to have a rogue monkey patch wreak invisible havoc randomly at some point in the future.

You can check that the patch is working by starting a Rails console (`RAILS_ENV=production bin/rails console`) and running the following:

```ruby
ActiveRecord::Base.connection.raw_connection.method(:busy_timeout).source_location
```

If the output is something like the following, then the patch is working:

```
=> ["/Users/[YOU]/path/to/euruko-2024/config/initializers/sqlite3_busy_timeout_patch.rb", 64]
```

### Running the Load Tests

Let's see how this patch affects the performance of our application. As always, let's restart our application server first. Go to your first terminal window/tab and use `Ctrl + C` to stop the server, then re-run `bin/serve` to restart it.

Once you have the server running with the initializer applied, you can run the `posts_index` load test again in another terminal window/tab:

```sh
oha -c 20 -z 10s -m POST http://localhost:3000/benchmarking/posts_index
```

<details>
  <summary>301 RPS (click to see full breakdown)</summary>

```
Summary:
  Success rate:	100.00%
  Total:	10.0029 secs
  Slowest:	0.6594 secs
  Fastest:	0.0036 secs
  Average:	0.0667 secs
  Requests/sec:	300.9133

  Total data:	191.02 MiB
  Size/request:	65.42 KiB
  Size/sec:	19.10 MiB

Response time histogram:
  0.004 [1]    |
  0.069 [1813] |■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
  0.135 [1072] |■■■■■■■■■■■■■■■■■■
  0.200 [62]   |■
  0.266 [21]   |
  0.332 [2]    |
  0.397 [1]    |
  0.463 [2]    |
  0.528 [4]    |
  0.594 [5]    |
  0.659 [7]    |

Response time distribution:
  10.00% in 0.0160 secs
  25.00% in 0.0528 secs
  50.00% in 0.0662 secs
  75.00% in 0.0752 secs
  90.00% in 0.0972 secs
  95.00% in 0.1179 secs
  99.00% in 0.2450 secs
  99.90% in 0.6318 secs
  99.99% in 0.6594 secs


Details (average, fastest, slowest):
  DNS+dialup:	0.0023 secs, 0.0011 secs, 0.0027 secs
  DNS-lookup:	0.0002 secs, 0.0000 secs, 0.0005 secs

Status code distribution:
  [200] 2990 responses

Error distribution:
  [20] aborted due to deadline
```
</details>

We won't see much of a difference on the nearly read-only `posts_index` action, but let's now look at the `posts_create` action:

```sh
oha -c 20 -z 10s -m POST http://localhost:3000/benchmarking/post_create
```

<details>
  <summary>1004 RPS (click to see full breakdown)</summary>

```
Summary:
  Success rate:	100.00%
  Total:	10.0011 secs
  Slowest:	0.3152 secs
  Fastest:	0.0025 secs
  Average:	0.0199 secs
  Requests/sec:	1004.0858

  Total data:	84.96 MiB
  Size/request:	8.68 KiB
  Size/sec:	8.50 MiB

Response time histogram:
  0.003 [1]    |
  0.034 [8628] |■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
  0.065 [1158] |■■■■
  0.096 [157]  |
  0.128 [33]   |
  0.159 [25]   |
  0.190 [10]   |
  0.221 [6]    |
  0.253 [3]    |
  0.284 [0]    |
  0.315 [1]    |

Response time distribution:
  10.00% in 0.0056 secs
  25.00% in 0.0088 secs
  50.00% in 0.0150 secs
  75.00% in 0.0251 secs
  90.00% in 0.0387 secs
  95.00% in 0.0491 secs
  99.00% in 0.0892 secs
  99.90% in 0.1881 secs
  99.99% in 0.2422 secs


Details (average, fastest, slowest):
  DNS+dialup:	0.0012 secs, 0.0007 secs, 0.0016 secs
  DNS-lookup:	0.0001 secs, 0.0000 secs, 0.0003 secs

Status code distribution:
  [200] 10022 responses

Error distribution:
  [20] aborted due to deadline
```
</details>

With this write-heavy action, we now see a noticeable improvement in performance. The requests per second increased from 816 to 1004 (23% increase), but more importantly the slowest request time decreased from 1.0928 seconds to 0.3152 seconds (3.5× decrease).

If you want, you can drop the Ruby version back down to 3.1.6 and re-run the load tests to see the 5+ seconds requests disappear as well. Here are the results that I got on my machine:

<details>
  <summary>682 RPS (click to see full breakdown)</summary>

```
Summary:
  Success rate:	100.00%
  Total:	10.0018 secs
  Slowest:	0.1966 secs
  Fastest:	0.0043 secs
  Average:	0.0293 secs
  Requests/sec:	682.0778

  Total data:	57.73 MiB
  Size/request:	8.69 KiB
  Size/sec:	5.77 MiB

Response time histogram:
  0.004 [1]    |
  0.023 [3438] |■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
  0.043 [1952] |■■■■■■■■■■■■■■■■■■
  0.062 [845]  |■■■■■■■
  0.081 [347]  |■■■
  0.100 [135]  |■
  0.120 [50]   |
  0.139 [22]   |
  0.158 [7]    |
  0.177 [2]    |
  0.197 [3]    |

Response time distribution:
  10.00% in 0.0086 secs
  25.00% in 0.0135 secs
  50.00% in 0.0232 secs
  75.00% in 0.0386 secs
  90.00% in 0.0582 secs
  95.00% in 0.0726 secs
  99.00% in 0.1039 secs
  99.90% in 0.1557 secs
  99.99% in 0.1966 secs


Details (average, fastest, slowest):
  DNS+dialup:	0.0012 secs, 0.0008 secs, 0.0015 secs
  DNS-lookup:	0.0001 secs, 0.0000 secs, 0.0002 secs

Status code distribution:
  [200] 6802 responses

Error distribution:
  [20] aborted due to deadline
```
</details>

We can compare this to the results (still using the `IMMEDIATE` transactions fix) when we comment out the patch application:

```ruby
# SQLiteBusyTimeoutMonkeypatch.apply_patch
```

On my machine, I saw:

<details>
  <summary>59 RPS (click to see full breakdown)</summary>

```
Summary:
  Success rate:	100.00%
  Total:	10.0024 secs
  Slowest:	5.3182 secs
  Fastest:	0.0049 secs
  Average:	0.1273 secs
  Requests/sec:	59.2861

  Total data:	4.84 MiB
  Size/request:	8.65 KiB
  Size/sec:	495.72 KiB

Response time histogram:
  0.005 [1]   |
  0.536 [562] |■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
  1.068 [0]   |
  1.599 [0]   |
  2.130 [0]   |
  2.662 [0]   |
  3.193 [0]   |
  3.724 [0]   |
  4.256 [0]   |
  4.787 [0]   |
  5.318 [10]  |

Response time distribution:
  10.00% in 0.0099 secs
  25.00% in 0.0129 secs
  50.00% in 0.0175 secs
  75.00% in 0.0377 secs
  90.00% in 0.1043 secs
  95.00% in 0.1601 secs
  99.00% in 5.2125 secs
  99.90% in 5.3182 secs
  99.99% in 5.3182 secs


Details (average, fastest, slowest):
  DNS+dialup:	0.0015 secs, 0.0008 secs, 0.0018 secs
  DNS-lookup:	0.0001 secs, 0.0000 secs, 0.0003 secs

Status code distribution:
  [200] 570 responses
  [500] 3 responses

Error distribution:
  [20] aborted due to deadline
```
</details>

When you don't have YJIT to paper over performance issues, you can really see the stark difference that this patch makes. The slowest request time decreased from 5.3182 seconds to 0.1966 seconds (27× decrease) and the requests per second increased from 59 to 682 (11× increase). Of course, you also see that some requests were still timing out without the patch as well.

### Conclusion

By applying the SQLite busy timeout patch, we were able to improve the long tail performance of our application, especially for write-heavy actions. This removed any 5+ second responses, removed any lingering errored responses, and generally improved the performance of the application.
