Gem::Specification.new do |s|
  s.name          = 'logstash-output-influxdb'
  s.version       = '0.1.3'
  s.licenses      = ['Apache License (2.0)']
  s.summary       = "This output lets you use logstash as a conduit to InfluxDB."
  s.description   = "This fork is a highly specific use case of wanting to be able to output arbitrary metrics to InfluxDB."
  s.authors       = ["Chris Hoffman"]
  s.email         = 'yarmiganosc@gmail.com'
  s.homepage      = "http://www.elasticsearch.org/guide/en/logstash/current/index.html"
  s.require_paths = ["lib"]

  s.files = `git ls-files`.split($\)+::Dir.glob('vendor/*')

  s.test_files = s.files.grep(%r{^(test|spec|features)/})

  s.metadata = {
    "logstash_plugin" => "true",
    "logstash_group"  => "output"
  }

  s.add_runtime_dependency "logstash-core", '>= 1.4.0', '< 2.0.0'

  s.add_runtime_dependency 'stud'
  s.add_runtime_dependency 'ftw', ['~> 0.0.40']

  s.add_development_dependency 'logstash-devutils'
end

