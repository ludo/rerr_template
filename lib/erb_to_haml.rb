require 'cgi'

module Rails
  class TemplateRunner
    def get_indent(line)
      line = line.to_s
      space_areas = line.scan(/^\s+/)
      space_areas.empty? ? 0 : (space_areas.first.size / 2)
    end

    def block_start?(line)
      block_starters = [/\s+do/, /^-\s+while/, /^-\s+module/, /^-\s+begin/,
                        /^-\s+case/, /^-\s+class/, /^-\s+unless/, /^-\s+for/, 
                        /^-\s+until/, /^-\s*if/]

      line = line.to_s
      line.strip =~ /^-/ && block_starters.any?{|bs| line.strip =~ bs}
    end

    def block_end?(line)
      line = line.to_s
      line.strip =~ /^-\send$/
    end

    def ie_block_start?(line)
      line = line.to_s
      line =~ /\[if/i && line =~ /IE/ && line.strip =~ /\]>$/
    end

    def ie_block_end?(line)
      line = line.to_s
      line =~ /<!\[endif\]/i
    end

    def comment_line?(line)
      line = line.to_s
      line.strip =~ /^\//
    end

    def indent(line, steps = 0)
      line = line.to_s
      exceptions = [/\s+else\W/, /^-\s+elsif/, /^-\s+when/, /^-\s+ensure/, /^-\s+rescue/]
      return if exceptions.any?{|ex| line.strip =~ ex}

      steps ||= 0
      line = line.to_s
      ("  " * steps) + line
    end

    def alter_lines(lines, altered_lines)
      altered_lines.each do |pair|
        line_number, text = pair
        lines[line_number] = text
      end
      lines
    end

    def indent_lines(lines, indented_lines)
      indented_lines.each do |pair|
        line_number, indent_by = pair
        lines[line_number] = indent(lines[line_number], indent_by)
      end
      lines
    end

    def remove_lines(lines, goner_lines)
      goner_lines.each do |i|
        lines[i] = nil
      end
      lines.compact
    end

    def erb_to_haml(folder)
      in_root do
        Dir[File.join(folder, "**/*.erb")].each do |origin|
          destination = origin.gsub(/\.erb$/, '.haml')
          run "html2haml -rx #{origin} #{destination}"

          # Auto-fix for haml indentation. Likely not very reliable.
          stack = []
          lines = File.readlines(destination)
          line_number = lines.size
          goner_lines = []
          indented_lines = []
          altered_lines = []
          inside_ie_block = false
          just_passed_ie_block = false

          lines.reverse_each do |line|
            line_number -= 1

            if just_passed_ie_block
              altered_lines << [line_number, line.sub('/', "/" + just_passed_ie_block)]
              just_passed_ie_block = false
            elsif ie_block_start?(line)
              goner_lines << line_number
              inside_ie_block = false
              stack.pop
              just_passed_ie_block = line.strip.chop
            elsif ie_block_end?(line)
              goner_lines << line_number
              inside_ie_block = true
              stack << get_indent(line)
            elsif inside_ie_block
              match = line.match(/<haml[^>]*>([^<]+)<\/haml/)
              string = match && match[1]
              string = string ? "= #{CGI::unescapeHTML(CGI::unescapeHTML(string.strip))}\n" : "#{line.strip}\n"
              altered_lines << [line_number, string]
              indented_lines << [line_number, stack.last]
            elsif block_end?(line)
              stack << 1
              goner_lines << line_number
            elsif block_start?(line)
              stack.pop
            else
              indented_lines << [line_number, stack.last]
            end
          end

          lines = alter_lines(lines, altered_lines)
          lines = indent_lines(lines, indented_lines)
          lines = remove_lines(lines, goner_lines)

          altered_lines = []
          indented_lines = [] 
          goner_lines = []

          line_number = -1
          lines.each_cons(3) do |three_lines|
            line_number += 1
            line2_number = line_number + 1
            middle_indented_by_one = (get_indent(three_lines[1]) - get_indent(three_lines[0]) == 1)
            top_indented_more = (get_indent(three_lines[0]) >= get_indent(three_lines[2]))
            commented = (three_lines[0].to_s.strip =~ /^\//)

            if(top_indented_more && middle_indented_by_one && !commented)
              if (three_lines[1].strip =~ /^=/)
                altered_lines << [line_number, (three_lines[0].rstrip + three_lines[1].lstrip)]
              else
                altered_lines << [line_number, (three_lines[0].rstrip + " " + three_lines[1].lstrip)]
              end
              goner_lines << line2_number
            end
          end

          lines = alter_lines(lines, altered_lines)
          lines = remove_lines(lines, goner_lines)

          File.open(destination, "w") do |f|
            f.write(lines.join)
          end

          File.delete(origin)
        end
      end
    end
  end
end