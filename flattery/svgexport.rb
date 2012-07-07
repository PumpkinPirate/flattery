# Copyright (c) 2010 Andrew Stoneman
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

require "flattery/utils.rb"

module Flattery
    module_function
    
    def export_svg()
        margin = 0.125
        entity = Sketchup.active_model.selection.first
        
        default_name = Sketchup.active_model.title
        if default_name == ""
            default_name = "flattened"
        end
        
        file_path = UI.savepanel "Save SVG File", "", default_name + ".svg"
        
        if !file_path
            return
        end
        
        has_textures = false
        file_dir = File.dirname(file_path)
        texture_dir = File.basename(file_path) + "-textures"
        last_index = -1
        pattern_number = 0
        tw = Sketchup.create_texture_writer()
        
        if container?(entity)
            f = File.new(file_path,  "w+")
            
            edges = get_entities(entity).find_all { |e| edge?(e) }
        
            group_trans = entity.transformation.clone
        
            plane = plane_for_entity(entity)
            plane_trans = Geom::Transformation.new([0,0,0], plane.normal.reverse)
            plane_trans.invert!
        
            transformation = plane_trans * group_trans
        
            min_x = Float::MAX
            min_y = Float::MAX
            max_x = -Float::MAX
            max_y = -Float::MAX
            edges.each do |e|
                p1 = e.start.position.transform(transformation)
                p2 = e.end.position.transform(transformation)
                min_x = [min_x, p1.x.to_f, p2.x.to_f].min
                min_y = [min_y, p1.y.to_f, p2.y.to_f].min
                max_x = [max_x, p1.x.to_f, p2.x.to_f].max
                max_y = [max_y, p1.y.to_f, p2.y.to_f].max
            end
        
            width = max_x - min_x + 2*margin
            height = max_y - min_y + 2*margin
        
            transformation = Geom::Transformation.new([margin - min_x, margin - min_y, 0]) * transformation
            
            int_lines = []
            ext_lines = []
            faces = []
            patterns = []
            
            get_entities(entity).each do |e|
                if edge?(e)
                    p1 = e.start.position.transform(transformation)
                    p2 = e.end.position.transform(transformation)
                    x1 = p1.x.to_f
                    y1 = p1.y.to_f
                    x2 = p2.x.to_f
                    y2 = p2.y.to_f
                    line = "<line x1=\"#{x1}\" y1=\"#{y1}\" x2=\"#{x2}\" y2=\"#{y2}\" stroke=\"rgb(0,0,0)\" stroke-width=\"0.0138888889\"/>"
                    if e.faces.length == 1
                        ext_lines.push(line)
                    else
                        int_lines.push(line)
                    end
                elsif face?(e)
                    points = e.vertices.map do |v|
                        p = v.position.transform(transformation)
                        "#{p.x.to_f},#{p.y.to_f}"
                    end
                    points = points.join(" ")
                    if e.material
                        if e.material.texture
                            index = tw.load(e, true)
                            texture_name = File.join(texture_dir, "#{index}.png")
                            
                            if index > last_index
                                last_index = index
                                
                                if !has_textures
                                    has_textures = true
                                    #FileUtils.mkdir(File.join(file_dir, texture_dir))
                                end
                                
                                tw.write(e, true, File.join(file_dir, texture_name))
                            end
                            
                            #     t            xy             uv
                            #                                         -1
                            # [a c d 0]   [x1 x2 x3 0]   [u1 u2 u3 0]
                            # [b e f 0] = [y1 y2 y3 0] * [v1 v2 v3 0]
                            # [0 0 1 0]   [1  1  1  0]   [1  1  1  0]
                            # [0 0 0 1]   [1  1  1  1]   [1  1  1  1]
                            
                            uv_helper = e.get_UVHelper(true, false, tw)
                            xy_points = []
                            uv_points = []
                            for i in 0..2
                                xyz = e.vertices[i].position
                                xy_points.push(xyz.transform(transformation))
                                uv_points.push(uv_helper.get_front_UVQ(xyz))
                            end
                            
                            xy = Geom::Transformation.new([xy_points[0].x, xy_points[0].y, 1, 1,
                                                           xy_points[1].x, xy_points[1].y, 1, 1,
                                                           xy_points[2].x, xy_points[2].y, 1, 1,
                                                           0, 0, 0, 1])
                            
                            # Scaling here combined with the width and height in the SVG
                            # get firefox to stop pixilating the textures.
                            uv = Geom::Transformation.new([10*uv_points[0].x, 10 - 10*uv_points[0].y, 1, 1,
                                                           10*uv_points[1].x, 10 - 10*uv_points[1].y, 1, 1,
                                                           10*uv_points[2].x, 10 - 10*uv_points[2].y, 1, 1,
                                                           0, 0, 0, 1])
                            
                            t = xy * uv.inverse
                            t = t.to_a
                            svg_matrix = "matrix(#{t[0]}, #{t[1]}, #{t[4]}, #{t[5]}, #{t[8]}, #{t[9]})"
                            patterns.push("<pattern id=\"texture#{pattern_number}\" patternUnits=\"userSpaceOnUse\"")
                            patterns.push("         x=\"0\" y=\"0\" width=\"10\" height=\"10\" viewBox=\"0 0 1 1\"")
                            patterns.push("         patternTransform=\"#{svg_matrix}\">")
                            patterns.push("  <image xlink:href=\"#{texture_name}\" x=\"0\" y=\"0\" ")
                            patterns.push("         width=\"1\" height=\"1\" preserveAspectRatio=\"none\"/>")
                            patterns.push("</pattern>")
                            
                            fill = "url('#texture#{pattern_number}')"
                            
                            pattern_number += 1
                        else
                            c = e.material.color
                            fill = "rgb(#{c.red},#{c.green},#{c.blue})"
                        end
                    else
                        fill = "rgb(255,255,255)"
                    end
                    faces.push("<polygon points=\"#{points}\" fill=\"#{fill}\"/>")
                end
            end
            
            f.puts('<?xml version="1.0" standalone="no"?>')
            f.puts('<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">')
            f.puts("<svg width=\"#{width}in\" height=\"#{height}in\" viewBox=\"0 0 #{width} #{height}\"")
            f.puts("     version=\"1.1\" xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\">")
            
            f.puts('<g id="faces">')
            f.puts('<defs>')
            f.puts(patterns.join("\n"))
            f.puts('</defs>')
            f.puts(faces.join("\n"))
            f.puts('</g>')
            
            f.puts('<g id="ext_lines">')
            f.puts(ext_lines.join("\n"))
            f.puts('</g>')
            
            f.puts('<g id="int_lines">')
            f.puts(int_lines.join("\n"))
            f.puts('</g>')
            
            f.puts('</svg>')
            f.close
        end
    
        
    end

end