require 'optparse'
require 'parser'
require 'parser/current'
require 'set'

class Processor < Parser::AST::Processor
  attr_reader :methods, :calls
  def initialize
    @methods = Set.new
    @calls   = Hash.new { |h,k| h[k] = [] }
  end

  def on_def(node)
    @method = node.children[0].to_s
    @methods.add(@method)
    super
    @method = nil
  end

  def on_send(node)
    target = node.children[1].to_s
    if @method && node.children[0].nil?
      @calls[@method] << target
    end
    super
  end
end

class DotRenderer
  BLACKLIST = Set.new(%w[log assert
    raise param gating_agent
    testing? __method__ request
    configatron soft_assert])

  def initialize(processor, out)
    @processor = processor
    @out = out
  end

  def render
    @out.puts("digraph G {")
    @out.puts(' page="8.5,11;"')

    @processor.calls.each do |src, dsts|
      @out.puts("  #{quote(src)} [style=filled];")
      dsts.each do |dst|
        unless BLACKLIST.include?(dst)
          @out.puts("  #{quote(src)} -> #{quote(dst)};")
        end
      end
    end

    @out.puts("}")
  end

  def quote(name)
    "\"#{name}\""
  end
end

def parse_args(options)
  optparse = OptionParser.new do |opts|
    opts.banner = <<-EOM
Usage: #{File.basename($0)} [options] path/to/file.rb

Options:
EOM

    opts.on('-d', '--defined', 'Print a list of defined methods') do
      options[:defined] = true
    end

    opts.on('-c', '--called', 'Print a list of called methods') do
      options[:called] = true
    end

    opts.on('-r', '--remote', 'Print a list of called-but-not-defined methods') do
      options[:remote] = true
    end

    opts.on('--dot=PATH', 'Write a dot callgraph') do |path|
      options[:dot] = path
    end
  end

  optparse.parse!

  unless ARGV.length == 1
    STDERR.puts optparse
    exit 1
  end

  return ARGV.first
end


def main
  options = {}
  path = parse_args(options)

  parser = parser = Parser::CurrentRuby.new
  buf = Parser::Source::Buffer.new(path).read
  ast = parser.parse(buf)

  p = Processor.new
  p.process(ast)

  if options[:defined]
    p.calls.keys.each do |m|
      puts m
    end
  elsif options[:called]
    p.calls.values.flatten.uniq.each do |m|
      puts m
    end
  elsif options[:remote]
    called = p.calls.values.flatten.uniq
    defined = p.calls.keys
    (called - defined).each do |m|
      puts m
    end
  end

  if options[:dot]
    f = File.new(options[:dot], 'w')
    DotRenderer.new(p, f).render
    f.close
  end
end

if $0 == __FILE__
  main
end
