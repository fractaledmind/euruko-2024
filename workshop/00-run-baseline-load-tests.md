## Run Baseline Load Tests

Before we start, let's establish a baseline. This is the starting point from which we will measure our progress. It's important to have a clear understanding of where we are now, so we can see how far we've come as we progress.

We will run two load tests to assess the current state of the application's performance; one for the `post_create` action and one for the `posts_index` action. We will run each test with 20 concurrent requests for 10 seconds.

We will run the read operation first since it can't have any effect on the write operation performance (while the inverse cannot be said). But first, it is often worth checking that the endpoint is responding as expected _before_ running a load test. So, let's make a single `curl` request first.

In one terminal window, start the Rails server:

```sh
bin/serve
```

In another, make a single `curl` request to the `posts_index` endpoint:

```sh
curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:3000/benchmarking/posts_index
```

You should see a `200` response. If you see that response, everything is working as expected. If you don't, you will need to troubleshoot the issue before proceeding.

Once we have verified that our Rails application is responding to the `benchmarking/posts_index` route as expected, we can run the load test and record the results.

As stated earlier, we will use the `oha` tool to run the load test. We will send waves of 20 concurrent requests, which is twice the number of Puma workers that our application has spun up. We will run the test for 10 seconds. The command to run the load test is as follows:

```sh
oha -c 20 -z 10s -m POST http://localhost:3000/benchmarking/posts_index
```

Running this on my 2021 M1 MacBook Pro (32 GB of RAM running MacOS 14.6.1) against our Rails 7.2.1 app with Ruby 3.1.6, I get the following results:

<details>
  <summary>242 RPS (click to see full breakdown)</summary>

```
Summary:
  Success rate:	100.00%
  Total:	10.0014 secs
  Slowest:	0.1948 secs
  Fastest:	0.0053 secs
  Average:	0.0828 secs
  Requests/sec:	242.4653

  Total data:	153.67 MiB
  Size/request:	65.43 KiB
  Size/sec:	15.37 MiB

Response time histogram:
  0.005 [1]   |
  0.024 [53]  |■■
  0.043 [115] |■■■■■■
  0.062 [507] |■■■■■■■■■■■■■■■■■■■■■■■■■■■■
  0.081 [578] |■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
  0.100 [499] |■■■■■■■■■■■■■■■■■■■■■■■■■■■
  0.119 [329] |■■■■■■■■■■■■■■■■■■
  0.138 [189] |■■■■■■■■■■
  0.157 [85]  |■■■■
  0.176 [43]  |■■
  0.195 [6]   |

Response time distribution:
  10.00% in 0.0474 secs
  25.00% in 0.0605 secs
  50.00% in 0.0790 secs
  75.00% in 0.1027 secs
  90.00% in 0.1257 secs
  95.00% in 0.1410 secs
  99.00% in 0.1636 secs
  99.90% in 0.1841 secs
  99.99% in 0.1948 secs


Details (average, fastest, slowest):
  DNS+dialup:	0.0022 secs, 0.0011 secs, 0.0032 secs
  DNS-lookup:	0.0002 secs, 0.0000 secs, 0.0007 secs

Status code distribution:
  [200] 2405 responses

Error distribution:
  [20] aborted due to deadline
```
</details>

It is worth noting that when I ran this load test 4 months ago on the same machine, things were notably worse. The p99.99 response time was **over 5 seconds**, the RPS was only **~40**, and some responses simply errored out. The fixes and improvements continuously made to Rails and the SQLite gem are clearly having a positive impact.

Now that we have the baseline for the `posts_index` action, we can move on to the `post_create` action. We will follow the same steps as above, but this time we will run the load test on the `post_create` endpoint.

With the Rails server still running in one terminal window, we can make a single `curl` request to the `post_create` endpoint in another:

```sh
curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:3000/benchmarking/post_create
```

Again, you should see a `200` response. If you don't, you will need to troubleshoot the issue before proceeding.

Once we have verified that our Rails application is responding to the `benchmarking/post_create` route as expected, we can run the load test and record the results.

```sh
oha -c 20 -z 10s -m POST http://localhost:3000/benchmarking/post_create
```

Running this on my 2021 M1 MacBook Pro (32 GB of RAM running MacOS 14.6.1) against our Rails 7.2.1 app with Ruby 3.1.6, I get the following results:

<details>
  <summary>95 RPS (click to see full breakdown)</summary>

```
Summary:
  Success rate:	100.00%
  Total:	10.0037 secs
  Slowest:	5.2195 secs
  Fastest:	0.0029 secs
  Average:	0.0387 secs
  Requests/sec:	94.9652

  Total data:	3.31 MiB
  Size/request:	3.65 KiB
  Size/sec:	339.07 KiB

Response time histogram:
  0.003 [1]   |
  0.525 [925] |■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
  1.046 [0]   |
  1.568 [0]   |
  2.090 [0]   |
  2.611 [0]   |
  3.133 [0]   |
  3.655 [0]   |
  4.176 [0]   |
  4.698 [0]   |
  5.220 [4]   |

Response time distribution:
  10.00% in 0.0037 secs
  25.00% in 0.0062 secs
  50.00% in 0.0094 secs
  75.00% in 0.0166 secs
  90.00% in 0.0397 secs
  95.00% in 0.0620 secs
  99.00% in 0.1307 secs
  99.90% in 5.2195 secs
  99.99% in 5.2195 secs


Details (average, fastest, slowest):
  DNS+dialup:	0.0021 secs, 0.0012 secs, 0.0025 secs
  DNS-lookup:	0.0001 secs, 0.0000 secs, 0.0004 secs

Status code distribution:
  [500] 661 responses
  [200] 269 responses

Error distribution:
  [20] aborted due to deadline
```
</details>

Immediately, it should jump out just how many `500` responses we are seeing. **71%** of the responses are returning an error status code. Suffice it to say, this is not at all what we want from our application. We also now see some requests taking over 5 seconds to complete, which is aweful. And our requests per second have plummeted to 2.5× to only **95**.

Our first challenge is to fix these performance issues.

> [!NOTE]
> If you want to ensure that you are running your load tests from a clean slate each time, you can reset your database (drop the database, create it, migrate it, seed it) before running the tests. You can do this by running the following command:
> ```sh
> DISABLE_DATABASE_ENVIRONMENT_CHECK=1 RAILS_ENV=production bin/rails db:reset
> ```
> This isn't _necessary_ for the purposes of this workshop, as the load test exact results don't change anything, but it can be helpful if you want to run fairer, more direct comparisons.

- - -

The next step is to begin improving performance. You will find that step's instructions in the `workshop/01-improving-performance.md` file.

There were no code changes in this step.
