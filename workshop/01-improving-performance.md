## Improving Performance

Before turning to fixing the noted performance problems, we should start by appreciating the value of using newer Ruby versions. Each new major version of Ruby includes a number of performance improvements over its predecessor. Let's upgrade our Ruby versions one by one and see how it affects our performance.

Upgrading is as simple as updating the value in the `.ruby-version` file in the root of our project.

### Upgrading Ruby to 3.2.5

The first upgrade is to move from Ruby 3.1.6 (our current version) to Ruby 3.2.5, which is the latest version in the 3.2 series. To do this, update the value in the `.ruby-version` file to `ruby-3.2.5`.

If you don't yet have Ruby 3.2.5 installed on your machine, you can install it with whatever mechanism you use to manage Ruby versions (e.g. `rbenv install 3.2.5` or `asdf install ruby 3.2.5`). Once you have Ruby 3.2.5 installed, run `bundle install` to download the necessary gems for the new Ruby version.

Once ready, again restart your Rails server process in your first terminal window/tab (`Ctrl + C` to stop then `bin/serve` to restart). You can confirm that the server is running with the new Ruby version by inspecting the output of that `bin/serve` command. You should see something like this:

```
[66056] * Puma version: 6.4.2 (ruby 3.2.5-p208) ("The Eagle of Durango")
```

Once you have the server running with the new Ruby version, you can run the `posts_index` load test again in another terminal window/tab:

```sh
oha -c 20 -z 10s -m POST http://localhost:3000/benchmarking/posts_index
```

I got these results:

<details>
  <summary>103 RPS (click to see full breakdown)</summary>

```
Summary:
  Success rate:	100.00%
  Total:	10.0030 secs
  Slowest:	5.2873 secs
  Fastest:	0.0062 secs
  Average:	0.1411 secs
  Requests/sec:	103.4685

  Total data:	64.09 MiB
  Size/request:	64.66 KiB
  Size/sec:	6.41 MiB

Response time histogram:
  0.006 [1]    |
  0.534 [1003] |■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
  1.062 [0]    |
  1.591 [0]    |
  2.119 [0]    |
  2.647 [0]    |
  3.175 [0]    |
  3.703 [0]    |
  4.231 [0]    |
  4.759 [0]    |
  5.287 [11]   |

Response time distribution:
  10.00% in 0.0315 secs
  25.00% in 0.0504 secs
  50.00% in 0.0740 secs
  75.00% in 0.1103 secs
  90.00% in 0.1466 secs
  95.00% in 0.1766 secs
  99.00% in 5.1785 secs
  99.90% in 5.2862 secs
  99.99% in 5.2873 secs


Details (average, fastest, slowest):
  DNS+dialup:	0.0009 secs, 0.0007 secs, 0.0011 secs
  DNS-lookup:	0.0001 secs, 0.0000 secs, 0.0002 secs

Status code distribution:
  [200] 1008 responses
  [500] 7 responses

Error distribution:
  [20] aborted due to deadline
```
</details>

Now, you will no doubt immediately notice that the requests per second has actually halved, and we now see some errored responses. Doesn't seem like Ruby 3.2.5 is helping us here at all. But, this is an important lesson in working with SQLite in Rails applications without any tuning. _Sometimes_, even in nearly read-only routes, your Active Record connection pool will have two connections contend with each other, and one will be forced to wait. And this contention can then cascade and eventually block all Active Record connections. This is what we're seeing here. Our benchmarking actions all sign in a random user, which means there is a chance of a write, even on the `posts/index` action, because if the randomly chosen user doesn't have an active session, a new session will be created for them. This is a write operation. And it can happen that two concurrent requests both need to create a new session and contend for SQLite's write lock. This is a common problem with SQLite and Rails, and it's why we're seeing both these errors and the many errors in the write-heavy `posts/create` action. We will explore and address this problem directly in a later step. For now, let's simply re-run the load test until we get a clean run.

For me, that happened on my next run, where I got these results:

<details>
  <summary>253 RPS (click to see full breakdown)</summary>

```
Summary:
  Success rate:	100.00%
  Total:	10.0023 secs
  Slowest:	0.2276 secs
  Fastest:	0.0043 secs
  Average:	0.0767 secs
  Requests/sec:	253.3405

  Total data:	160.19 MiB
  Size/request:	65.25 KiB
  Size/sec:	16.02 MiB

Response time histogram:
  0.004 [1]   |
  0.027 [117] |■■■■■■
  0.049 [616] |■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
  0.071 [533] |■■■■■■■■■■■■■■■■■■■■■■■■■■■
  0.094 [468] |■■■■■■■■■■■■■■■■■■■■■■■■
  0.116 [353] |■■■■■■■■■■■■■■■■■■
  0.138 [215] |■■■■■■■■■■■
  0.161 [126] |■■■■■■
  0.183 [60]  |■■■
  0.205 [17]  |
  0.228 [8]   |

Response time distribution:
  10.00% in 0.0293 secs
  25.00% in 0.0456 secs
  50.00% in 0.0709 secs
  75.00% in 0.1026 secs
  90.00% in 0.1341 secs
  95.00% in 0.1532 secs
  99.00% in 0.1829 secs
  99.90% in 0.2223 secs
  99.99% in 0.2276 secs


Details (average, fastest, slowest):
  DNS+dialup:	0.0011 secs, 0.0007 secs, 0.0049 secs
  DNS-lookup:	0.0001 secs, 0.0000 secs, 0.0003 secs

Status code distribution:
  [200] 2514 responses

Error distribution:
  [20] aborted due to deadline
```
</details>

Compared to the previous results, the slowest response time actually increased a bit from 0.1948 seconds to 0.2276 seconds (17% worse), the fastest response time dropped from 0.0053 seconds to 0.0043 seconds (23% better), the average response time increased from 0.0828 seconds to 0.0767 seconds (8% better), and the requests per second increased from 242 to 253 (5% better). All in all, nothing mind-blowing, but still a solid improvement.

Next, let's try the `posts/create` action:

```sh
oha -c 20 -z 10s -m POST http://localhost:3000/benchmarking/post_create
```

As with the baseline when running Ruby 3.1.6, we see loads of errored responses. This makes the actual performance numbers very random and thus less interesting. But, we can still see that the requests per second is around 110, which is a bit better than the baseline. For now, let's not consider this load test until we fix the SQLite contention issue.

<details>
  <summary>110 RPS (click to see full breakdown)</summary>

```
Summary:
  Success rate:	100.00%
  Total:	10.0047 secs
  Slowest:	5.3114 secs
  Fastest:	0.0028 secs
  Average:	0.0730 secs
  Requests/sec:	109.8488

  Total data:	3.70 MiB
  Size/request:	3.51 KiB
  Size/sec:	378.39 KiB

Response time histogram:
  0.003 [1]    |
  0.534 [1066] |■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
  1.065 [0]    |
  1.595 [0]    |
  2.126 [0]    |
  2.657 [0]    |
  3.188 [0]    |
  3.719 [0]    |
  4.250 [0]    |
  4.781 [0]    |
  5.311 [12]   |

Response time distribution:
  10.00% in 0.0053 secs
  25.00% in 0.0070 secs
  50.00% in 0.0102 secs
  75.00% in 0.0151 secs
  90.00% in 0.0261 secs
  95.00% in 0.0423 secs
  99.00% in 5.2525 secs
  99.90% in 5.3091 secs
  99.99% in 5.3114 secs


Details (average, fastest, slowest):
  DNS+dialup:	0.0008 secs, 0.0006 secs, 0.0009 secs
  DNS-lookup:	0.0001 secs, 0.0000 secs, 0.0002 secs

Status code distribution:
  [500] 788 responses
  [200] 291 responses

Error distribution:
  [20] aborted due to deadline
```
</details>

### Upgrading Ruby to 3.3.5

Next, let's upgrade from Ruby 3.2.5 (our current version) to Ruby 3.3.5, which is the latest version in the 3.3 series. To do this, update the value in the `.ruby-version` file to `ruby-3.3.5`.

If you don't yet have Ruby 3.3.5 installed on your machine, you can install it with whatever mechanism you use to manage Ruby versions (e.g. `rbenv install 3.3.5` or `asdf install ruby 3.3.5`). Once you have Ruby 3.3.5 installed, run `bundle install` to download the necessary gems for the new Ruby version.

Once ready, again restart your Rails server process in your first terminal window/tab (`Ctrl + C` to stop then `bin/serve` to restart). You can confirm that the server is running with the new Ruby version by inspecting the output of that `bin/serve` command. You should see something like this:

```
[25595] * Puma version: 6.4.2 (ruby 3.3.5-p100) ("The Eagle of Durango")
```

Once you have the server running with the new Ruby version, you can run the `posts_index` load test again in another terminal window/tab:

```sh
oha -c 20 -z 10s -m POST http://localhost:3000/benchmarking/posts_index
```

If you get a run that included `500` responses, you can ignore that run and try again. The goal is to get a run that includes only `200` responses. My first clean run resulted in the following:

<details>
  <summary>381 RPS (click to see full breakdown)</summary>

```
Summary:
  Success rate:	100.00%
  Total:	10.0011 secs
  Slowest:	0.2370 secs
  Fastest:	0.0029 secs
  Average:	0.0525 secs
  Requests/sec:	381.2593

  Total data:	240.84 MiB
  Size/request:	65.02 KiB
  Size/sec:	24.08 MiB

Response time histogram:
  0.003 [1]    |
  0.026 [1287] |■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
  0.050 [183]  |■■■■
  0.073 [1411] |■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
  0.097 [682]  |■■■■■■■■■■■■■■■
  0.120 [136]  |■■■
  0.143 [70]   |■
  0.167 [16]   |
  0.190 [3]    |
  0.214 [2]    |
  0.237 [2]    |

Response time distribution:
  10.00% in 0.0148 secs
  25.00% in 0.0173 secs
  50.00% in 0.0609 secs
  75.00% in 0.0724 secs
  90.00% in 0.0848 secs
  95.00% in 0.1030 secs
  99.00% in 0.1354 secs
  99.90% in 0.1961 secs
  99.99% in 0.2370 secs


Details (average, fastest, slowest):
  DNS+dialup:	0.0009 secs, 0.0007 secs, 0.0011 secs
  DNS-lookup:	0.0001 secs, 0.0000 secs, 0.0002 secs

Status code distribution:
  [200] 3793 responses

Error distribution:
  [20] aborted due to deadline
```
</details>

Slowest:	0.2370 secs
Fastest:	0.0029 secs
Average:	0.0525 secs
Requests/sec:	381.2593

Slowest:	0.2276 secs
Fastest:	0.0043 secs
Average:	0.0767 secs
Requests/sec:	253.3405

This is a noticeably better improvement than the jump from 3.1 to 3.2! The fastest response time dropped from 0.0043 seconds to 0.0029 seconds (48% better), the average response time decreased from 0.0767 seconds to 0.0525 seconds (46% better), and the requests per second increased from 253 to 381 (51% better). A 50% performance improvement is a great result!

I believe this is primarily due to the fact that Rails 7.2.1 and Ruby 3.3.x, when used together, will automatically use the new Ruby YJIT compiler. The YJIT compiler is designed to improve the performance of Ruby code by compiling it to machine code at runtime. This can result in significant performance improvements for Ruby applications, as we have seen here.

So, for any Rails app, but especially for SQLite on Rails apps, upgrading to Ruby 3.3.x and using Rails >= 7.2 is a great idea!

- - -

