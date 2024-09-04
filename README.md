# README

This is an app built for demonstration purposes for the [EuRuKo 2024 conference](https://2024.euruko.org) held in Sarajevo, Bosnia & Herzegovina on September 11-13, 2024.

The application is a basic "Hacker News" style app with `User`s, `Post`s, and `Comment`s. The seeds file will create ~100 users, ~1,000 posts, and ~10 comments per post (so ~10,000 comments). Every user has the same password: `password`, so you can sign in as any user to test the app.

This application runs on Ruby >= 3.1, Rails 7.2.1, and SQLite 3.46.1 (gem version 2.0.4).

## Setup

First you need to clone the repository to your local machine:

```sh
git clone git@github.com:fractaledmind/euruko-2024.git
cd euruko-2024
```

After cloning the repository, install the dependencies:

```sh
bundle install
```

I have built the repository to be usable out-of-the-box. It contains a seeded production database, precompiled assets, and a binscript to start the server in production mode. The only other things you will need besides the RubyGems dependencies are multiple different Ruby versions and the load testing tool `oha`.

### Setup Ruby Versions

By default, this repository uses Ruby 3.1.6, which is the most recent point release on the 3.1 branch. As a part of the exploration of the performance impact of different Ruby versions on SQLite-backed Rails applications, we will  be testing the following Ruby versions:

```
ruby-3.3.5
ruby-3.2.5
ruby-3.1.6
```

Please make sure you have each of these Ruby versions installed on your machine. If you are using `rbenv`, you can install them with commands like the following:

```sh
rbenv install 3.3.5
```

Or, if you are using `asdf`, you can install them like so:

```sh
asdf install ruby 3.3.5
```

If you manage Ruby versions some other way, I'm sure you know how to install new Ruby versions with your tool of choice.

### Setup Load Testing

Load testing can be done using the [`oha` CLI utility](https://github.com/hatoo/oha), which can be installed on MacOS via [homebrew](https://brew.sh):

```sh
brew install oha
```

and on Windows via [winget](https://github.com/microsoft/winget-cli):

```sh
winget install hatoo.oha
```

or using their [precompiled binaries](https://github.com/hatoo/oha?tab=readme-ov-file#installation) on other platforms.

## Load Testing

Throughout this workshop, we will be load testing the application to observe how our various changes impact the performance of the application. In order to perform the load testing, you will need to run the web server in the `production` environment. I have provided a binscript to make this easier. To start the production server, run the following command:

```sh
bin/serve
```

This simply a shortcut for the following command:

```sh
RAILS_ENV=production RELAX_SSL=true RAILS_LOG_LEVEL=warn WEB_CONCURRENCY=10 RAILS_MAX_THREADS=5 bin/rails server
```

The `RELAX_SSL` environment variable is necessary to allow you to use `http://localhost`. The `RAILS_LOG_LEVEL` is set to `warn` to reduce the amount of logging output. Set `WEB_CONCURRENCY` to the number of cores you have on your laptop. I am on an M1 Macbook Pro with 10 cores, and thus I set the value to 10. The `RAILS_MAX_THREADS` controls the number of threads per worker. I left it at the default of 5, but you can tweak it to see how it affects performance.

With your server running in one terminal window, you can use the load testing utility to test the app in another terminal window. Here is the shape of the command you will use to test the app:

```sh
oha -c N -z 10s -m POST http://localhost:3000/benchmarking/PATH
```

`N` is the number of concurrent requests that `oha` will make. I recommend running a large variety of different scenarios with different values of `N`. Personally, I scale up from 1 to 256 concurrent requests, doubling the number of concurrent requests each time. In general, when `N` matches your `WEB_CONCURRENCY` number, this is mostly likely the sweet spot for this app.

`PATH` can be any of the benchmarking paths defined in the app. The app has a few different paths that you can test. From the `routes.rb` file:

```ruby
namespace :benchmarking do
  post "post_create"
  post "comment_create"
  post "post_destroy"
  post "comment_destroy"
  post "post_show"
  post "posts_index"
  post "user_show"
end
```

You can validate that the application is properly set up for load testing by serving the application in one terminal window/tab (via `bin/serve`) and then running the following `curl` command in another terminal window/tab:

```sh
curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:3000/benchmarking/posts_index
```

If this returns `200`, then next ensure that you can run an `oha` command like the following:

```sh
oha -c 1 -z 1s -m POST http://localhost:3000/benchmarking/posts_index
```

If this runs successfully, then you are ready to begin the workshop.

## Workshop

You will find the workshop instructions in the `workshop/` directory. The workshop is broken down into a series of steps, each of which is contained in a separate markdown file. The workshop is designed to be self-guided, but I am available to help if you get stuck. Please feel free to reach out to me on Twitter at [@fractaledmind](https://twitter.com/fractaledmind) if you have any questions.

The first step is to [run some baseline load tests](workshop/00-run-baseline-load-tests.md). Once you have completed that step, you can move on to the next step, which will be linked at the bottom of each step.
