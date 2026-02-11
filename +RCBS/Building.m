classdef Building < dynamicprops & handle
    properties
        simulation  % RCBS.Simulation object
        outdoorTempFunc % function handle: datetime -> temperature (degC)
        storeyList = {} % names
    end
    
    methods
        function obj = Building()
            obj.simulation = RCBS.Simulation(obj);
            obj.outdoorTempFunc = @(t) 10; % default constant 10°C
        end
        
        function addStorey(obj, name)
            if isprop(obj, name)
                error('Storey "%s" already exists.', name);
            end
            p = addprop(obj, name);
            obj.(name) = RCBS.Storey(name, obj);
            obj.storeyList{end+1} = name;
        end
        
        function simulate(obj, varargin)
            % B.simulate(duration)
            % or B.simulate(years, months, days, hours, minutes)
            %
            % Example:
            %   B.simulate(hours(5))
            %   B.simulate(0,0,1,0,0)  % 1 day
            
            % --- Case 1: duration input (preferred)
            if numel(varargin) == 1 && isa(varargin{1}, 'duration')
                simDuration = varargin{1};
                
            % --- Case 2: numeric [y,m,d,h,min] input
            elseif numel(varargin) == 5
                [y,m,d,h,minu] = deal(varargin{:});
                simDuration = years(y) + calmonths(m) + days(d) + hours(h) + minutes(minu);
                
            else
                error('Usage: B.simulate(duration) or B.simulate(y,m,d,h,min)');
            end
            
            % --- Validation
            if isempty(obj.simulation.startDate)
                error('Set B.simulation.startDate before calling simulate().');
            end
            if isempty(obj.simulation.timeStep) || obj.simulation.timeStep <= seconds(0)
                error('Set B.simulation.timeStep (duration) before calling simulate().');
            end
            
            % --- Compute total duration in seconds (approx for months/years)
            % Convert to seconds (1 year ≈ 365.25 days)
            dt_seconds = seconds(obj.simulation.timeStep);
            endDate = obj.simulation.startDate + simDuration;
            totalSeconds = seconds(endDate - obj.simulation.startDate);
            
            % --- Run the simulation
            obj.simulation.run(totalSeconds);
        end

        function visualize(obj)
            disp('Generating schematic visualization...');
            
            figure('Name', 'Building Schematic Model', 'NumberTitle', 'off', 'Color', 'w');
            ax = axes;
            hold(ax, 'on');
            
            % --- Layout Parameters ---
            zone_w = 3; zone_h = 2;
            wall_th = 0.5;
            storey_spacing = zone_h + 2*wall_th + 2.0;
            zone_spacing = zone_w + 2*wall_th + 2.0;
            outdoor_conn_offset = 0.3;
            
            % --- STEP 1: AUTOMATIC ZONE LAYOUT CALCULATION ---
            source_zones = {};
            target_zones = {};
            all_zone_names = {};
            
            for s_idx = 1:numel(obj.storeyList)
                sname = obj.storeyList{s_idx};
                storey = obj.(sname);
                for z_idx = 1:numel(storey.zoneList)
                    zname = storey.zoneList{z_idx};
                    zone = storey.(zname);
                    full_zone_name = sprintf('%s.%s', sname, zname);
                    all_zone_names{end+1} = full_zone_name;
                    
                    if isprop(zone, 'crossRes')
                        for cr_idx = 1:numel(zone.crossRes)
                            res = zone.crossRes{cr_idx};
                            if res.n1.zone == zone
                                source_zones{end+1} = sprintf('%s.%s', res.n1.zone.storey.name, res.n1.zone.name);
                                target_zones{end+1} = sprintf('%s.%s', res.n2.zone.storey.name, res.n2.zone.name);
                            end
                        end
                    end
                end
            end
            
            zone_positions = containers.Map('KeyType', 'char', 'ValueType', 'any');
            if ~isempty(source_zones)
                zone_graph = graph(source_zones, target_zones, [], all_zone_names);
                h_fig_temp = figure('Visible', 'off');
                p_layout = plot(zone_graph, 'Layout', 'force');
                
                x_data = p_layout.XData;
                y_data = p_layout.YData;
                
                rot_angle = deg2rad(-45);
                rot_matrix = [cos(rot_angle) -sin(rot_angle); sin(rot_angle) cos(rot_angle)];
                rotated_points = rot_matrix * [x_data; y_data];
                x_data = rotated_points(1, :);
                y_data = rotated_points(2, :);

                for i = 1:numel(p_layout.NodeLabel)
                    zone_name = p_layout.NodeLabel{i};
                    pos = [x_data(i) * zone_spacing, y_data(i) * storey_spacing];
                    zone_positions(zone_name) = pos;
                end
                close(h_fig_temp);
            else
                 for i = 1:numel(all_zone_names)
                     pos = [(i-1) * zone_spacing, 0];
                     zone_positions(all_zone_names{i}) = pos;
                 end
            end

            % --- STEP 2: Main Drawing Loop ---
            drawn_cross_res = {};
            for s_idx = 1:numel(obj.storeyList)
                sname = obj.storeyList{s_idx};
                storey = obj.(sname);
                for z_idx = 1:numel(storey.zoneList)
                    zname = storey.zoneList{z_idx};
                    zone = storey.(zname);
                    
                    full_zone_name = sprintf('%s.%s', sname, zname);
                    pos = zone_positions(full_zone_name);
                    x0 = pos(1);
                    y0 = pos(2);
                    
                    terminals.T_main = [x0 + zone_w/2, y0 + zone_h/2];
                    
                    wall_nodes = find(contains({zone.nodes.name}, 'Wall') | contains({zone.nodes.name}, 'Roof'));
                    if ~isempty(wall_nodes)
                        rectangle(ax, 'Position', [x0-wall_th, y0-wall_th, zone_w+2*wall_th, zone_h+2*wall_th], 'LineWidth', 1, 'FaceColor', [0.95 0.95 0.95], 'EdgeColor', [0.8 0.8 0.8]);
                    end

                    rectangle(ax, 'Position', [x0, y0, zone_w, zone_h], 'LineWidth', 2);
                    plot(ax, terminals.T_main(1), terminals.T_main(2), 'k.', 'MarkerSize', 20);
                    text(ax, terminals.T_main(1) + 0.1, terminals.T_main(2), {'T_{main}', zone.name}, ...
                        'HorizontalAlignment', 'left', 'VerticalAlignment', 'middle', 'FontWeight', 'bold', 'Color', [0.8 0 0]);
                    
                    % Walls and Roofs
                    for w_idx = 1:numel(wall_nodes)
                        node = zone.nodes(wall_nodes(w_idx));
                        res_to_main_idx = find(arrayfun(@(r) isequal(r.n2, wall_nodes(w_idx)), zone.resistors));
                        res_to_out_idx = find(arrayfun(@(r) isequal(r.n1, wall_nodes(w_idx)) && strcmp(r.n2, 'outdoor'), zone.resistors));
                        if ~isempty(res_to_main_idx) && ~isempty(res_to_out_idx)
                            R_val = zone.resistors(res_to_main_idx(1)).R;
                            terminals.T_wall = [terminals.T_main(1), y0 + zone_h + wall_th/2];
                            terminals.Wall_outdoor = [terminals.T_main(1), y0 + zone_h + wall_th + outdoor_conn_offset];
                            terminals.Wall_indoor  = [terminals.T_main(1), y0 + zone_h  - outdoor_conn_offset];
                            plot(ax, [terminals.T_main(1), terminals.Wall_indoor(1)], [terminals.T_main(2), terminals.Wall_indoor(2)], 'k-');
                            draw_resistor(ax, terminals.Wall_indoor, terminals.T_wall, R_val);
                            draw_resistor(ax, terminals.T_wall, terminals.Wall_outdoor, R_val);
                            draw_outdoor_node(ax, terminals.Wall_outdoor, 'top');
                            plot(ax, terminals.T_wall(1), terminals.T_wall(2), 'k.', 'MarkerSize', 20);
                            text(ax, terminals.T_wall(1) - 0.1, terminals.T_wall(2), ['T_{' node.name '}'], 'HorizontalAlignment', 'right', 'VerticalAlignment', 'middle');
                            p_cap = [terminals.T_wall(1) + 0.6, terminals.T_wall(2)];
                            draw_capacitor(ax, terminals.T_wall, p_cap, node.C);
                        end
                    end
                    
                    % Windows (on bottom)
                    win_resistors = find(contains({zone.resistors.name}, 'Window'));
                    for win_idx = 1:numel(win_resistors)
                        res = zone.resistors(win_resistors(win_idx));
                        x_pos = x0 + zone_w/2 + (win_idx-1- (numel(win_resistors)-1)/2)*1.2;
                        win_w = 3 * wall_th;
                        win_h = wall_th;
                        terminals.Window_inner = [x_pos, y0 - wall_th/2];
                        terminals.Window_outer = [x_pos, y0 - wall_th - outdoor_conn_offset];
                        rectangle(ax, 'Position', [x_pos - win_w/2, y0 - win_h, win_w, win_h], 'FaceColor', [0.3 0.7 1 0.5], 'EdgeColor', 'b', 'LineWidth', 2);
                        plot(ax, [terminals.T_main(1), terminals.Window_inner(1)], [terminals.T_main(2), terminals.Window_inner(2)], 'k-');
                        draw_resistor(ax, terminals.Window_inner, terminals.Window_outer, res.R);
                        draw_outdoor_node(ax, terminals.Window_outer, 'bottom');
                    end
                    
                    % Internal Mass
                    im_nodes = find(contains({zone.nodes.name}, 'IntMass'));
                     for i = 1:numel(im_nodes)
                        im_node_idx = im_nodes(i);
                        node = zone.nodes(im_node_idx);
                        terminals.T_intmass = [x0 + 0.5, y0 + zone_h/2];
                        plot(ax, terminals.T_intmass(1), terminals.T_intmass(2), 'k.', 'MarkerSize', 20);
                        text(ax, terminals.T_intmass(1) - 0.1, terminals.T_intmass(2) - 0.3, ['T_{' node.name '}'], 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom');
                        res_idx_found = find(arrayfun(@(r) isequal(r.n2, im_node_idx), zone.resistors));
                        if ~isempty(res_idx_found)
                           draw_resistor(ax, terminals.T_intmass, terminals.T_main, zone.resistors(res_idx_found).R);
                        end
                        p_cap = [terminals.T_intmass(1), terminals.T_intmass(2) + 0.5];
                        draw_capacitor(ax, terminals.T_intmass, p_cap, node.C);
                     end

                    % Inter-Zone Connections
                    if isprop(zone, 'crossRes')
                        for cr_idx = 1:numel(zone.crossRes)
                            res = zone.crossRes{cr_idx};
                            if ismember(res.name, drawn_cross_res), continue; end
                            if res.n1.zone ~= zone, continue; end
                            other_zone = res.n2.zone;
                            other_full_name = sprintf('%s.%s', other_zone.storey.name, other_zone.name);
                            other_pos = zone_positions(other_full_name);
                            other_x0 = other_pos(1);
                            other_y0 = other_pos(2);
                            
                            if abs(y0 - other_y0) > abs(x0 - other_x0)
                                if y0 > other_y0
                                    p1 = [x0+zone_w/2, y0-wall_th]; p2 = [other_x0+zone_w/2, other_y0+zone_h+wall_th];
                                else
                                    p1 = [x0+zone_w/2, y0+zone_h+wall_th]; p2 = [other_x0+zone_w/2, other_y0-wall_th];
                                end
                            else
                                if x0 > other_x0
                                    p1 = [x0-wall_th, y0+zone_h/2]; p2 = [other_x0+zone_w+wall_th, other_y0+zone_h/2];
                                else
                                    p1 = [x0+zone_w+wall_th, y0+zone_h/2]; p2 = [other_x0-wall_th, other_y0+zone_h/2];
                                end
                            end
                            draw_resistor(ax, p1, p2, res.R);
                            drawn_cross_res{end+1} = res.name;
                        end
                    end
                end
            end
            
            hold(ax, 'off');
            axis(ax, 'equal', 'tight');
            set(ax, 'Visible', 'off');

            % --- Helper functions ---
            function str = format_value(val)
                if val >= 1e9, str = sprintf('%.1fG', val/1e9);
                elseif val >= 1e6, str = sprintf('%.1fM', val/1e6);
                elseif val >= 1e3, str = sprintf('%.1fk', val/1e3);
                elseif val < 1 && val > 0, str = sprintf('%.1fm', val*1e3);
                else, str = sprintf('%.2g', val);
                end
            end
            
            function draw_resistor(ax, p1, p2, val)
                p1=p1(:)'; p2=p2(:)'; v=p2-p1; dist=norm(v); uv=v/dist; uv_perp=[-uv(2), uv(1)];
                line_len = min(0.3, dist/3); N=5; zig_h = 0.1;
                p_zz_start = p1 + line_len * uv;
                p_line2_start = p2 - line_len * uv;
                plot(ax, [p1(1), p_zz_start(1)], [p1(2), p_zz_start(2)], 'k-');
                plot(ax, [p_line2_start(1), p2(1)], [p_line2_start(2), p2(2)], 'k-');
                plot(ax, [p1(1) p2(1)], [p1(2) p2(2)], 'k.', 'MarkerSize', 15);
                zz_points = p_zz_start;
                zz_uv = (p_line2_start - p_zz_start) / (2*N);
                for i=1:2*N, zz_points=[zz_points; zz_points(end,:)+zz_uv+zig_h*uv_perp*(-1)^i]; end
                zz_points(end,:) = p_line2_start;
                plot(ax, zz_points(:,1), zz_points(:,2), 'k-');
                angle = atan2d(v(2), v(1));
                mid_point = (p1+p2)/2;
                label_pos = mid_point + 0.1 * uv_perp;
                text(ax, label_pos(1), label_pos(2), format_value(val), 'Rotation', angle, ...
                    'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom');
            end
            
            function draw_capacitor(ax, p_term, p_cap_center, val)
                p_term = p_term(:)'; p_cap_center = p_cap_center(:)';
                plate_len = 0.3; plate_gap = 0.05;
                v = p_cap_center - p_term;
                uv = v / norm(v);
                uv_perp = [-uv(2), uv(1)];
                p1 = p_cap_center - plate_len/2 * uv_perp;
                p2 = p_cap_center + plate_len/2 * uv_perp;
                plate1_p1 = p1 - plate_gap * uv;
                plate1_p2 = p2 - plate_gap * uv;
                plate2_p1 = p1 + plate_gap * uv;
                plate2_p2 = p2 + plate_gap * uv;
                plot(ax, [plate1_p1(1) plate1_p2(1)], [plate1_p1(2) plate1_p2(2)], 'k', 'LineWidth', 2);
                plot(ax, [plate2_p1(1) plate2_p2(1)], [plate2_p1(2) plate2_p2(2)], 'k', 'LineWidth', 2);
                plot(ax, [p_term(1) p_cap_center(1)], [p_term(2) p_cap_center(2)], 'k-');
                plot(ax, p_term(1), p_term(2), 'k.', 'MarkerSize', 15);
                angle = atan2d(v(2), v(1));
                label_pos = p_cap_center + 0.15 * uv_perp;
                text(ax, label_pos(1), label_pos(2), format_value(val), 'Rotation', angle, ...
                    'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom');
            end
            
            function draw_outdoor_node(ax, p, label_pos)
                if nargin < 3, label_pos = 'bottom'; end
                plot(ax, p(1), p(2), 'o', 'MarkerSize', 8, 'MarkerFaceColor', [0.2 0.6 1], 'MarkerEdgeColor', 'k');
                if strcmp(label_pos, 'bottom')
                    text(ax, p(1), p(2) - 0.15, 'T_{outdoor}', 'HorizontalAlignment', 'center', 'VerticalAlignment', 'top');
                else % top
                    text(ax, p(1), p(2) + 0.15, 'T_{outdoor}', 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom');
                end
            end
        end
        
        function temps = getAllZoneTemps(obj)
            % helper: collect main node temps of all zones
            temps = containers.Map();
            for i = 1:numel(obj.storeyList)
                sname = obj.storeyList{i};
                storey = obj.(sname);
                for j=1:numel(storey.zoneList)
                    zname = storey.zoneList{j};
                    zone = storey.(zname);
                    temps(sprintf('%s.%s', sname, zname)) = zone.getMainTemp();
                end
            end
        end
    end
end