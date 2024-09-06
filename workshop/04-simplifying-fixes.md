## Simplifying Fixes

In the last two steps, we have addressed the two major issues that we identified in our baseline load tests. We have resolved the `500` error responses by opening _immediate_ transactions in our `post_create` action. We have also resolved the 5+ second responses by ensuring that Ruby's GVL is released when queries are waiting to retry to acquire SQLite's write lock.

Neither fix is profoundly combersome, and I wanted to ensure that you were comfortable understanding the problems and the solutions (especially _why_ the solutions work). But, you don't actually need to manually make these changes in your Rails application. You can simply add a gem to your project that will automatically make these changes for you.

### The Solution

Instead of manually patching our application, we can address both of these pain points by simply bringing into our project the [`activerecord-enhancedsqlite3-adapter` gem](https://github.com/fractaledmind/activerecord-enhancedsqlite3-adapter). This gem is a zero-configuration drop-in enhancement for the `sqlite3` adapter that comes with Rails. It will automatically open transactions in immediate mode, and it will also ensure that whenever SQLite is waiting for a query to acquire the write lock that other Puma workers can continue to process requests. In addition, it will back port some nice ActiveRecord features that aren't yet in a point release, like deferred foreign key constraints, custom return columns, and generated columns.

To add the `activerecord-enhancedsqlite3-adapter` gem to your project, simply run the following command:

```sh
bundle add activerecord-enhancedsqlite3-adapter
```

Simply by adding the gem to your `Gemfile` you automatically get all of the gem's goodies. You don't need to configure anything.

So, we can now remove the manual changes we made to our application. First, delete the `config/initializers/sqlite3_busy_timeout_patch.rb` file

```sh
rm config/initializers/sqlite3_busy_timeout_patch.rb
```

Then, remove the `default_transaction_mode: IMMEDIATE` line from your `config/database.yml` file:

```sh
sed -i '' '/default_transaction_mode: IMMEDIATE/d' config/database.yml
```

The enhanced adapter gem will supply both fixes automatically for us.

### Running the Load Tests

Let's rerun our load tests and ensure things have stayed improved. We first need to restart our application server so that it picks up and uses the enhanced adapter. So, `Ctrl + C` to stop the running server, then re-run the `bin/serve` command in that terminal window/tab.

Then, in the other terminal window/tab, run the `post_create` load test again:

```sh
oha -c 20 -z 10s -m POST http://localhost:3000/benchmarking/post_create
```

which gave me these results:

<details>
  <summary>1017 RPS (click to see full breakdown)</summary>

```
Summary:
  Success rate:	100.00%
  Total:	10.0005 secs
  Slowest:	0.2814 secs
  Fastest:	0.0024 secs
  Average:	0.0197 secs
  Requests/sec:	1017.0507

  Total data:	86.05 MiB
  Size/request:	8.68 KiB
  Size/sec:	8.60 MiB

Response time histogram:
  0.002 [1]    |
  0.030 [8415] |■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
  0.058 [1412] |■■■■■
  0.086 [212]  |
  0.114 [54]   |
  0.142 [28]   |
  0.170 [10]   |
  0.198 [9]    |
  0.226 [5]    |
  0.254 [3]    |
  0.281 [2]    |

Response time distribution:
  10.00% in 0.0054 secs
  25.00% in 0.0086 secs
  50.00% in 0.0147 secs
  75.00% in 0.0248 secs
  90.00% in 0.0382 secs
  95.00% in 0.0503 secs
  99.00% in 0.0902 secs
  99.90% in 0.1971 secs
  99.99% in 0.2785 secs


Details (average, fastest, slowest):
  DNS+dialup:	0.0013 secs, 0.0007 secs, 0.0018 secs
  DNS-lookup:	0.0001 secs, 0.0000 secs, 0.0003 secs

Status code distribution:
  [200] 10151 responses

Error distribution:
  [20] aborted due to deadline
```
</details>

We see that there are still no `500` errored responses, requests per second remains above 1,000, and the slowest request is still under 300ms. The `activerecord-enhancedsqlite3-adapter` gem has successfully addressed the two major issues we identified in our baseline load tests.

### Conclusion

While it is important to understand _what_ the enhanced adapter is doing, and some of you may actually prefer to have the code that fixes the problems we have discussed in your repository, it is nice that we can simply add a gem to our project and have these issues automatically addressed.
