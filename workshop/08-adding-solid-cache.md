## Adding Solid Cache

In addition to a job backend, a full-featured Rails application often needs a cache backend. Modern Rails provides a database-backed default cache store named [Solid Cache](https://github.com/rails/solid_cache).

### The Implementation

We install it like any other gem:

```sh
bundle add solid_cache
```

Like with Solid Queue, we need to configure Solid Cache to use a separate database. We can do this by adding a new database configuration to our `config/database.yml` file:

```yaml
cache: &cache
  <<: *default
  migrations_paths: db/cache_migrate
  database: storage/<%= Rails.env %>-cache.sqlite3
```

We then need to ensure that our `production` environment uses this `cache` database, like so:

```yaml
production:
  primary:
    <<: *default
    database: storage/production.sqlite3
  queue: *queue
  cache: *cache
```

With the new cache database configured, we can install Solid Cache into our application with that database

```sh
RAILS_ENV=production DATABASE=cache bin/rails solid_cache:install
```

This will create the migration files in the `db/cache_migrate` directory and set Solid Cache to be the production cache store. You should see output like:

```
        gsub  config/environments/production.rb
      create  config/solid_cache.yml
        gsub  config/database.yml
      create  db/cache_schema.rb
```

Once installed, we can then run the load the generated schema like so:

```sh
RAILS_ENV=production rails db:prepare DATABASE=cache
```

> [!NOTE]
> We are doing all of this in the `production` environment for this workshop. If you were setting up Solid Cache in `development`, you would also need to enable the cache in the `development` environment. This is done by running the `dev:cache` task:
>```sh
>bin/rails dev:cache
>```
> You want to see the following output:
>```
>Development mode is now being cached.
>```

With Solid Cache enabled for the `production` environment, we can finally ensure that Solid Cache itself will use our new cache database. Luckily, the new default, is that Solid Cache expects you to a separate `cache` database. And this is precisely what we have setup. Check the configuration file at `config/solid_cache.yml` and ensure it looks like this:

```yaml
default: &default
  database: cache
  store_options:
    # Cap age of oldest cache entry to fulfill retention policies
    # max_age: <%= 60.days.to_i %>
    max_size: <%= 256.megabytes %>
    namespace: <%= Rails.env %>

development:
  <<: *default

test:
  <<: *default

production:
  <<: *default
```

### Using Solid Cache

With Solid Cache now fully integrated into our application, we can use it like any other Rails cache store. Let's confirm that everything is working as expecting by opening the Rails console:

```sh
RAILS_ENV=production bin/rails console
```

write to the `Rails.cache` object:

```ruby
Rails.cache.write(:key, "value")
```

If we then read that key back from the cache:

```ruby
Rails.cache.read(:key)
```

You should see the value `"value"` returned.

You can confirm that this entry was stored in the Solid Cache database by checking:

```ruby
SolidCache::Entry.count
```

and also:

```ruby
SolidCache::Entry.first.attributes
```

This output will confirm that Solid Cache is working as expected!

With caching now enabled in our application, we can use Solid Cache to cache expensive operations, such as database queries, API calls, or view partials, to improve the performance of our application.

We can cache the rendering of the posts partial in the `posts/index.html.erb` view like so:

```erb
<td>
  <% cache post do %>
    <%= render post %>
  <% end %>
</td>
```

### Conclusion

In this step, we added the Solid Cache gem, backed by a separate SQLite database, to our application. With Solid Cache installed and setup, the next step is to consider how to enhance SQLite with extensions.
