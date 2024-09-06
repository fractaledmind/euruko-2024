## Controling SQLite Compilation

Because SQLite is simply a single executable, it is easy to control the actual compilation of SQLite. The `sqlite3-ruby` gem allows us to control the compilation flags used to compile the SQLite executable. We can set the compilation flags via the `BUNDLE_BUILD__SQLITE3` environment variable set in the `.bundle/config` file. Bundler allows you set set such configuration via the `bundle config set` command. To control SQLite compilation, you use the `bundle config set build.sqlite3` command passing the `--with-sqlite-cflags` argument.

### The Test

Before we set the actual compilation flags we want for SQLite, let's first confirm that this process works. We will need a compilation flag that will be easy to check in the Rails console. Luckily, whether or not SQLite was compiled with thread-safety is a check that the `sqlite3-ruby` gem provides via `SQLite3.threadsafe?`.

So, let's first check the current value of `SQLite.threadsafe?`. First, we need to start a Rails console:

```sh
RAILS_ENV=production bin/rails c
```

Then, check the current value:

```irb
> SQLite3.threadsafe?
=> true
```

Ok, so by default SQLite is compiled with thread-safety. Let's now try to compile SQLite with thread-safety off.

As described above, we can set the compilation flags via the `bundle config set build.sqlite3` command:

```sh
bundle config set build.sqlite3 \
  "--with-sqlite-cflags='-DSQLITE_THREADSAFE=0'"
```

If it doesn't already exist, this command will create a `.bundle/config` file in your project directory. Its contents should look something like:

```yaml
---
BUNDLE_BUILD__SQLITE3: "--with-sqlite-cflags=' -DSQLITE_THREADSAFE=0'"
```

Finally, in order to ensure that SQLite is compiled from source, we need to specify in the `Gemfile` that the SQLite gem should use the `ruby` platform version.

```ruby
gem "sqlite3", ">= 2.0", force_ruby_platform: true
```

When you now run `bundle install`, you should see something like:

```
Fetching sqlite3 2.0.4
Installing sqlite3 2.0.4 with native extensions
```

Compiling SQLite from source can take a while, so be patient. Once it is done, you can start a Rails console and check the value of `SQLite3.threadsafe?` now. You should hopefully see:

```irb
> SQLite3.threadsafe?
=> false
```

If you see `false`, this confirms that the compilation flags were set correctly, that SQLite was compiled with thread-safety off, and that our Rails app is using the custom compiled SQLite executable. Now, we want to set the actually desired compilation flags for SQLite, which requires undoing the thread-safety flag we just set.

If you ever want to undo custom compilation, you will not only need to remove the `build.sqlite3` configuration and the `force_ruby_platform` option from the `Gemfile`, but you will also need to delete the `sqlite3` gem from your system. This can be done with the following command:

```sh
rm -rf $(bundle show sqlite3)
```

After that, simply run `bundle install` again to reinstall the `sqlite3` gem.

### The Implementation

The [SQLite docs recommend 12 flags](https://www.sqlite.org/compile.html#recommended_compile_time_options) for a 5% improvement. The `sqlite3-ruby` gem needs some of the features recommended to be omitted, and some are useful for Rails apps. These 6 flags are my recommendation for a Rails app, and can be set using the following command:

```sh
bundle config set build.sqlite3 \
  "--with-sqlite-cflags='
      -DSQLITE_DQS=0
      -DSQLITE_DEFAULT_MEMSTATUS=0
      -DSQLITE_LIKE_DOESNT_MATCH_BLOBS
      -DSQLITE_MAX_EXPR_DEPTH=0
      -DSQLITE_OMIT_SHARED_CACHE
      -DSQLITE_USE_ALLOCA'"
```

Typically, the `.bundle/config` file is removed from source control, but we add it back to make this app more portable. Note, however, that this does restrict individual configuration of Bundler. This requires a change to the `.gitignore` file. Find this portion of your `.gitignore` file (should be near the top):

```
# Ignore bundler config.
/.bundle
```

And add this line:

```
!.bundle/config
```

Again, make sure that the SQLite gem forces the `ruby` platform version:

```ruby
gem "sqlite3", ">= 2.0", force_ruby_platform: true
```

Run `bundle install` again to compile SQLite with the new flags. And we're done.

### Conclusion

With SQLite custom compiled, the next step is to setup the repository to work with branch-specific databases.