require 'pg'
require 'opensearch'
require 'date'
require 'dotenv/load'

def webhook(data)
  body = JSON.parse(data[:event]['body']).transform_keys(&:to_sym)
  puts body

  begin
    record = save_to_database(body)

    index_opensearch(record.transform_keys(&:to_sym))
  rescue PG::Error => e
    puts "PostgreSQL error: #{e.message}"
    { statusCode: 500, body: JSON.generate('Failed to insert data into the database.') }
  rescue => e
    puts "Error: #{e.message}"
    { statusCode: 500, body: JSON.generate('Failed to index data to OpenSearch.') }
  end
end

private

def save_to_database(data)
  db_params = {
    host: ENV['DB_HOST'],
    port: 5432,
    dbname: ENV['DB_NAME'],
    user: ENV['DB_USER'],
    password: ENV['DB_PASSWORD']
  }
  conn = PG.connect(db_params)

  sources = conn.exec("SELECT * FROM sources").map do |row|
    {
      id: row['id'],
      name: row['name']
    }
  end

  data[:source_id] = sources.find { |source| source[:name] == data[:source] }[:id]

  query = "
    INSERT INTO posts (source_id, title, description, link, guid, publish_date, created_at, updated_at)
    VALUES ($1, $2, $3, $4, $5, $6, NOW(), NOW())
    RETURNING *;
  "
  result = conn.exec_params(query, [data[:source_id], data[:title], data[:description], data[:link], data[:guid], data[:pub_date]])
  conn.close

  result.first
end

def index_opensearch(data)
  client = OpenSearch::Client.new(
    url: ENV['OPENSEARCH_URL'],
  )

  body = {
    source: data[:source_id],
    title: data[:title],
    description: data[:description],
    publish_date: DateTime.parse(data[:publish_date]).to_date,
  }

  client.index(
    index: "intuitus_posts_production",
    id: data[:id],
    body: body
  )
end
