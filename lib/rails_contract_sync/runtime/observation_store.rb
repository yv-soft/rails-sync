require "json"
require "fileutils"

module RailsContractSync
  module Runtime
    class ObservationStore
      def initialize(path)
        @path = path
      end

      def append(hash)
        FileUtils.mkdir_p(File.dirname(@path))
        File.open(@path, "a") { |f| f.puts(JSON.generate(hash)) }
      end

      def all
        return [] unless File.exist?(@path)

        File.readlines(@path, chomp: true).reject(&:empty?).map { |line| JSON.parse(line) }
      end

      def clear
        File.delete(@path) if File.exist?(@path)
      end
    end
  end
end
