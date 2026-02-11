classdef Simulation < handle
    properties
        building
        startDate datetime
        timeStep duration
        results % struct: times, T (matrix), nodeNames
        t % current simulation datetime during run
    end
    
    methods
        function obj = Simulation(building)
            obj.building = building;
            obj.timeStep = minutes(10); % default
            obj.startDate = datetime(2000,1,1);
        end
        
        function run(obj, totalSeconds)
            if isempty(obj.timeStep) || obj.timeStep <= 0
                error('Set a valid simulation.timeStep (duration).');
            end
            dt = seconds(obj.timeStep);
            nsteps = floor(totalSeconds / dt);
        
            % Build node map (your existing buildNodeMap function is correct)
            [nodeGlobalMap, nodesInfo] = obj.buildNodeMap();
            N = numel(nodesInfo);
        
            % Initial state vector x (temperatures)
            x = zeros(N,1);
            Cvec = zeros(N,1);
            for i = 1:N
                x(i) = nodesInfo{i}.T0;
                Cvec(i) = nodesInfo{i}.C;
            end
        
            % Prepare results struct (same as before)
            % ... (code for preparing `res` struct) ...
            res = struct();
            res.Time = obj.startDate + seconds((0:nsteps)' * dt);
            res.OutdoorTemperature = zeros(nsteps+1,1);
            storeyNames = obj.building.storeyList;
            zoneKeys = keys(nodeGlobalMap.zoneMain);
            for s = 1:numel(storeyNames)
                sname = storeyNames{s};
                storey = obj.building.(sname);
                res.(sname) = struct();
                for z = 1:numel(storey.zoneList)
                    zname = storey.zoneList{z};
                    res.(sname).(zname) = struct();
                    res.(sname).(zname).T = zeros(nsteps+1,1);
                    res.(sname).(zname).heatInput = zeros(nsteps+1,1);
                end
            end

            % Store Initial Conditions (t=0)
            obj.t = obj.startDate;
            res.OutdoorTemperature(1) = obj.building.outdoorTempFunc(obj.t);
            for qi = 1:numel(zoneKeys)
                key = zoneKeys{qi};
                gidx = nodeGlobalMap.zoneMain(key);
                parts = split(key,'.');
                sname = parts{1};
                zname = parts{2};
                res.(sname).(zname).T(1) = x(gidx);
            end

            % --- Simulation loop using a STABLE IMPLICIT SOLVER ---
            for k = 1:nsteps
                currentTime = obj.startDate + seconds((k-1)*dt);
                obj.t = currentTime;
        
                % --- Build the linear system A*x_new = b ---
                A = zeros(N, N);
                b = zeros(N, 1);
        
                Tout = obj.building.outdoorTempFunc(currentTime);
                
                % --- MODIFICATION: Updated Heat Source Logic ---
                Q_sources = zeros(N, 1);
                zoneHeatMap = containers.Map(); % For logging results
                
                % Iterate through all zones to find their heat sources
                allZones = values(nodeGlobalMap.zoneObj);
                uniqueZones = unique([allZones{:}]); % Get each zone object only once
                
                for zi = 1:numel(uniqueZones)
                    zone = uniqueZones(zi);
                    zoneKey = sprintf('%s.%s', zone.storey.name, zone.name);
                    zoneHeatMap(zoneKey) = 0; % Initialize log
                    
                    % For each heat source defined in the zone...
                    for hs_idx = 1:numel(zone.heatSources)
                        hs = zone.heatSources(hs_idx);
                        
                        % Find the global index of its target node
                        targetNodeFullName = sprintf('%s.%s.%s', zone.storey.name, zone.name, hs.nodeName);
                        g_idx = nodeGlobalMap.fullName(targetNodeFullName);
                        
                        % Calculate heat and add it to the Q_sources vector
                        Qw = hs.hf(obj.building);
                        Q_sources(g_idx) = Q_sources(g_idx) + Qw;
                        
                        % If the source is on the main node, log it for plotting
                        if strcmp(hs.nodeName, 'T_main')
                           zoneHeatMap(zoneKey) = zoneHeatMap(zoneKey) + Qw;
                        end
                    end
                end
                
                % Populate A matrix and b vector for each node's equation
                for i = 1:N
                    % Start with the capacitance term for the diagonal of A
                    A(i,i) = Cvec(i) / dt;
                    % The b vector starts with the influence of the previous temperature
                    b(i) = (Cvec(i) / dt) * x(i) + Q_sources(i);

                    % Add influence of all connected resistors
                    for r = 1:numel(nodesInfo{i}.resList)
                        rr = nodesInfo{i}.resList{r};
                        G = 1 / rr.R; % Conductance
                        
                        if strcmp(rr.toType, 'outdoor')
                            A(i,i) = A(i,i) + G;
                            b(i) = b(i) + G * Tout;
                        else % Connection to another node j
                            j = rr.toIndex;
                            A(i,i) = A(i,i) + G;
                            A(i,j) = A(i,j) - G;
                        end
                    end
                end
        
                % --- Solve for the new temperature vector x ---
                x = A \ b; % This is the core of the implicit solver
        
                % Store results for the end of the step (at index k+1)
                res.OutdoorTemperature(k+1) = Tout; % Store temp used in calculation
                for qi = 1:numel(zoneKeys)
                    key = zoneKeys{qi};
                    gidx = nodeGlobalMap.zoneMain(key);
                    parts = split(key,'.');
                    sname = parts{1};
                    zname = parts{2};
                    res.(sname).(zname).T(k+1) = x(gidx);
                    res.(sname).(zname).heatInput(k+1) = zoneHeatMap(key);
                end
            end
        
            obj.results = res;
        end
        
        function [nodeGlobalMap, nodesInfo] = buildNodeMap(obj)
            nodesInfo = {};
            nodeGlobalMap = struct();
            nodeGlobalMap.zoneMain = containers.Map();
            nodeGlobalMap.zoneObj  = containers.Map();
            nodeGlobalMap.fullName = containers.Map();
            
            idx = 1;
            for s = 1:numel(obj.building.storeyList)
                sname = obj.building.storeyList{s};
                storey = obj.building.(sname);
                for z = 1:numel(storey.zoneList)
                    zname = storey.zoneList{z};
                    zone = storey.(zname);
                    for n = 1:zone.getNodeCount()
                        nd = zone.nodes(n);
                        if nd.C > 0
                            fullName = sprintf('%s.%s.%s', sname, zname, nd.name);
                            info.name = fullName;
                            info.C = nd.C;
                            info.T0 = nd.T;
                            info.resList = {};
                            nodesInfo{idx} = info; %#ok<AGROW>
                            
                            nodeGlobalMap.fullName(fullName) = idx;
                            
                            if nd.isMain
                                zoneKey = sprintf('%s.%s', sname, zname);
                                nodeGlobalMap.zoneMain(zoneKey) = idx;
                                nodeGlobalMap.zoneObj(zoneKey) = zone;
                            end
                            idx = idx + 1;
                        end
                    end
                end
            end
            
            % --- Second pass: Symmetrically build all connections ---
            for s = 1:numel(obj.building.storeyList)
                sname = obj.building.storeyList{s};
                storey = obj.building.(sname);
                for z = 1:numel(storey.zoneList)
                    zname = storey.zoneList{z};
                    zone = storey.(zname);
                    
                    % Process local resistors within the zone
                    for r = 1:numel(zone.resistors)
                        res = zone.resistors(r);
                        n1_name = zone.nodes(res.n1).name;
                        n1_fullName = sprintf('%s.%s.%s', sname, zname, n1_name);
                        g_idx1 = nodeGlobalMap.fullName(n1_fullName);
                        
                        if ischar(res.n2) && strcmp(res.n2, 'outdoor')
                            nodesInfo{g_idx1}.resList{end+1} = struct('R', res.R, 'toType', 'outdoor', 'toIndex', []);
                        else
                            n2_name = zone.nodes(res.n2).name;
                            n2_fullName = sprintf('%s.%s.%s', sname, zname, n2_name);
                            g_idx2 = nodeGlobalMap.fullName(n2_fullName);
                            nodesInfo{g_idx1}.resList{end+1} = struct('R', res.R, 'toType', 'local', 'toIndex', g_idx2);
                            nodesInfo{g_idx2}.resList{end+1} = struct('R', res.R, 'toType', 'local', 'toIndex', g_idx1);
                        end
                    end
                    
                    % Process cross-zone resistors
                    if isprop(zone, 'crossRes')
                        for r = 1:numel(zone.crossRes)
                           res = zone.crossRes{r};
                           % Process the resistor only if this zone is the 'n1' side.
                           % This ensures each cross-zone link is created only ONCE.
                           if res.n1.zone == zone 
                               zone1_key = sprintf('%s.%s', res.n1.zone.storey.name, res.n1.zone.name);
                               zone2_key = sprintf('%s.%s', res.n2.zone.storey.name, res.n2.zone.name);
                               
                               g_idx1 = nodeGlobalMap.zoneMain(zone1_key);
                               g_idx2 = nodeGlobalMap.zoneMain(zone2_key);
                               
                               nodesInfo{g_idx1}.resList{end+1} = struct('R', res.R, 'toType', 'cross', 'toIndex', g_idx2);
                               nodesInfo{g_idx2}.resList{end+1} = struct('R', res.R, 'toType', 'cross', 'toIndex', g_idx1);
                           end
                        end
                    end
                end
            end
        end

        
        function plotResults(obj)
            res = obj.results;
            times = res.Time;
        
            figure;
            hold on;
            legendEntries = {};
        
            % Iterate storeys
            storeyNames = fieldnames(res);
            storeyNames = setdiff(storeyNames, {'Time','OutdoorTemperature'}); % ignore global fields
        
            for s = 1:numel(storeyNames)
                sname = storeyNames{s};
                zoneNames = fieldnames(res.(sname));
        
                for z = 1:numel(zoneNames)
                    zname = zoneNames{z};
                    Tseries = res.(sname).(zname).T;
                    plot(times, Tseries);
                    legendEntries{end+1} = sprintf('%s.%s', sname, zname); %#ok<AGROW>
                end
            end
        
            % Optional: plot outdoor temperature
            if isfield(res,'OutdoorTemperature')
                plot(times, res.OutdoorTemperature, '--k', 'LineWidth',1.5);
                legendEntries{end+1} = 'OutdoorTemperature';
            end
        
            xlabel('Time');
            ylabel('Temperature (°C)');
            title('Simulation Temperatures');
            legend(legendEntries,'Interpreter','none','Location','best');
            grid on;
            datetick('x','keeplimits');
            hold off;
        end

    end
end
