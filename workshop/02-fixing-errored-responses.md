## Fixing Errored Responses

As of today, a SQLite on Rails application will struggle with concurrency. Although Rails, since version 7.1.0, ensures that your SQLite databases are running in [WAL mode](https://www.sqlite.org/wal.html), this is insufficient to ensure quality performance for web applications under concurrent load.

### The Problem

The first problem to fix are all of the `500` error responses that we saw in our `post_create` load test and occassionally in the `posts_index` test. If you look at the server logs, you will see the error being thrown is:

```
ActiveRecord::StatementInvalid (SQLite3::BusyException: database is locked):
```

This is the [`SQLITE_BUSY` exception](https://www.sqlite.org/rescode.html#busy).

I will save you hours, if not days, of debugging and investigation and tell you that these errors are caused by Rails not opening transactions in what SQLite calls ["immediate mode"](https://www.sqlite.org/lang_transaction.html#deferred_immediate_and_exclusive_transactions). In order to ensure only one write operation occurs at a time, SQLite uses a write lock on the database. Only one connection can hold the write lock at a time. By default, SQLite interprets the `BEGIN TRANSACTION` command as initiating a _deferred_ transaction. This means that SQLite will not attempt to acquire the database write lock until a write operation is made inside that transaction. In contrast, an _immediate_ transaction will attempt to acquire the write lock immediately upon the `BEGIN IMMEDIATE TRANSACTION` command being issued.

Opening deferred transactions in a web application with multiple connections open to the database _nearly guarantees_ that you will see a large number of `SQLite3::BusyException` errors. This is because SQLite is unable to retry the write operation within the deferred transaction if the write lock is already held by another connection because any retry would risk the transaction operating against a different snapshot of the database state.

Opening _immediate_ transactions, on the other hand, is safer in a multi-connection environment because SQLite can safely retry the transaction opening command until the write lock is available, since the transaction won't grab a snapshot until the write lock is acquired.

While future versions of Rails will address this issue by opening immediate transactions by default, we must fix this issue ourselves in the meantime.

So, how do we ensure that our Rails application makes all transactions immediate?

### The Solution

As of [version 1.6.9](https://github.com/sparklemotion/sqlite3-ruby/releases/tag/v1.6.9), the [`sqlite3-ruby` gem](https://github.com/sparklemotion/sqlite3-ruby) allows you to configure the default transaction mode with the `default_transaction_mode` option when initializing a new `SQLite3::Database` instance. Since Rails passes any top-level keys in your `database.yml` configuration directly to the `sqlite3-ruby` database initializer, you can easily ensure that Rails’ SQLite transactions are all run in IMMEDIATE mode by updating your `default` configuration in the `database.yml` file:

```yaml
default: &default
  adapter: sqlite3
  pool: <%= ENV. fetch("RAILS_MAX_THREADS") { 5 }%›
  timeout: 5000
  default_transaction_mode: IMMEDIATE
```

This will ensure that all transactions in your Rails application are run in immediate mode. Let's run our load tests again to see if this fixes the `500` errors.

### Running the Load Tests

As always, let's restart our application server first. Go to your first terminal window/tab and use `Ctrl + C` to stop the server, then re-run `bin/serve` to restart it.

Once you have the server running with the new Ruby version, you can run the `posts_index` load test again in another terminal window/tab:

```sh
oha -c 20 -z 10s -m POST http://localhost:3000/benchmarking/posts_index
```

You should not see any `500` errors this time:

<details>
  <summary>294 RPS (click to see full breakdown)</summary>

```
Summary:
  Success rate:	100.00%
  Total:	10.0004 secs
  Slowest:	0.7988 secs
  Fastest:	0.0032 secs
  Average:	0.0682 secs
  Requests/sec:	294.0875

  Total data:	186.72 MiB
  Size/request:	65.46 KiB
  Size/sec:	18.67 MiB

Response time histogram:
  0.003 [1]    |
  0.083 [2623] |■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
  0.162 [247]  |■■■
  0.242 [22]   |
  0.321 [7]    |
  0.401 [2]    |
  0.481 [2]    |
  0.560 [9]    |
  0.640 [2]    |
  0.719 [5]    |
  0.799 [1]    |

Response time distribution:
  10.00% in 0.0512 secs
  25.00% in 0.0579 secs
  50.00% in 0.0625 secs
  75.00% in 0.0673 secs
  90.00% in 0.0830 secs
  95.00% in 0.1065 secs
  99.00% in 0.2179 secs
  99.90% in 0.6678 secs
  99.99% in 0.7988 secs


Details (average, fastest, slowest):
  DNS+dialup:	0.0012 secs, 0.0007 secs, 0.0017 secs
  DNS-lookup:	0.0002 secs, 0.0000 secs, 0.0006 secs

Status code distribution:
  [200] 2921 responses

Error distribution:
  [20] aborted due to deadline
```
</details>

But, we have seen that the `posts_index` load test can sometimes run smoothly. Let's run the `post_create` load test again to see if the `500` errors are gone:

```sh
oha -c 20 -z 10s -m POST http://localhost:3000/benchmarking/post_create
```

No errors! The `500` errors are gone:

<details>
  <summary>816 RPS (click to see full breakdown)</summary>

```
Summary:
  Success rate:	100.00%
  Total:	10.0010 secs
  Slowest:	1.0928 secs
  Fastest:	0.0022 secs
  Average:	0.0245 secs
  Requests/sec:	816.3180

  Total data:	69.03 MiB
  Size/request:	8.68 KiB
  Size/sec:	6.90 MiB

Response time histogram:
  0.002 [1]    |
  0.111 [7821] |■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
  0.220 [249]  |■
  0.329 [36]   |
  0.438 [27]   |
  0.547 [4]    |
  0.657 [4]    |
  0.766 [0]    |
  0.875 [0]    |
  0.984 [1]    |
  1.093 [1]    |

Response time distribution:
  10.00% in 0.0033 secs
  25.00% in 0.0050 secs
  50.00% in 0.0116 secs
  75.00% in 0.0245 secs
  90.00% in 0.0540 secs
  95.00% in 0.0968 secs
  99.00% in 0.2148 secs
  99.90% in 0.4419 secs
  99.99% in 1.0928 secs


Details (average, fastest, slowest):
  DNS+dialup:	0.0007 secs, 0.0006 secs, 0.0009 secs
  DNS-lookup:	0.0000 secs, 0.0000 secs, 0.0002 secs

Status code distribution:
  [200] 8144 responses

Error distribution:
  [20] aborted due to deadline
```
</details>

### Conclusion

We have confirmed that this simple configuration change has fixed the `500` errors in our Rails application. By setting the `default_transaction_mode` option to `IMMEDIATE` in the `database.yml` file, we can ensure that all transactions in our Rails application are run in immediate mode. And this will help prevent `500` errors caused by SQLite's default deferred transaction mode.

