classdef Zone < handle
    properties
        name
        building % parent building
        storey   % parent storey
        crossRes
        
        % Node list: struct array with fields: name, C, T, isMain (logical)
        nodes = struct('name',{}, 'C',{}, 'T',{}, 'isMain', {});
        % Resistors: struct array with fields: n1 (index), n2 (index or 'outdoor'), R, name
        resistors = struct('n1',{}, 'n2',{}, 'R',{}, 'name',{});
        
        % heat source functions: cell of function handles hf(building) -> W
        heatSources = struct('hf',{}, 'nodeName',{});
        
        % defaults (modifiable)
        C_main = 1e5; % J/K default main capacitance
        R_default = 5e-3; % K/W default resistor
    end
    
    methods
        function obj = Zone(name, building, storey)
            obj.name = name;
            obj.building = building;
            obj.storey = storey;
            obj.crossRes = {};
            % create main node
            obj.nodes(1).name = 'T_main';
            obj.nodes(1).C = obj.C_main;
            obj.nodes(1).T = 20; % default initial temp
            obj.nodes(1).isMain = true;
        end
        
        function idx = addNode(obj, nodename, C, T0)
            if nargin<4, T0 = obj.nodes(1).T; end
            nd.name = nodename;
            nd.C = C;
            nd.T = T0;
            nd.isMain = false;
            obj.nodes(end+1) = nd;
            idx = numel(obj.nodes);
        end
        
        function addWall(obj, R_wall, C_wall, T0, name)
            % Corrected T-Network Model: R_wall is the TOTAL resistance,
            % so we split it into two halves for the model.
            if nargin<5, name = sprintf('Wall%d', sum(strncmp({obj.nodes.name},'Wall',4))+1); end
            idx = obj.addNode(sprintf('%s', name), C_wall, T0);
            % resistor main <-> wall (uses R/2)
            obj.resistors(end+1) = struct('n1', 1, 'n2', idx, 'R', R_wall/2, 'name', [name '_m']);
            % resistor wall <-> outdoor (uses R/2)
            obj.resistors(end+1) = struct('n1', idx, 'n2', 'outdoor', 'R', R_wall/2, 'name', [name '_o']);
        end
        
        function addRoof(obj, R_roof, C_roof, T0, name)
            % Corrected T-Network Model for roofs as well
            if nargin<5, name = sprintf('Roof%d', sum(strncmp({obj.nodes.name},'Roof',4))+1); end
            idx = obj.addNode(name, C_roof, T0);
            obj.resistors(end+1) = struct('n1', 1, 'n2', idx, 'R', R_roof/2, 'name', [name '_m']);
            obj.resistors(end+1) = struct('n1', idx, 'n2', 'outdoor', 'R', R_roof/2, 'name', [name '_o']);
        end
        
        function addWindow(obj, R_window, name)
            if nargin<3, name = sprintf('Window%d', sum(strncmp({obj.resistors.name},'Window',6))+1); end
            % model as direct resistor from main node to outdoor
            obj.resistors(end+1) = struct('n1', 1, 'n2', 'outdoor', 'R', R_window, 'name', name);
        end
        
        function addInternalMass(obj, R_int, C_int, T0, name)
            if nargin<5, name = sprintf('IntMass%d', sum(strncmp({obj.nodes.name},'Int',3))+1); end
            idx = obj.addNode(name, C_int, T0);
            obj.resistors(end+1) = struct('n1', 1, 'n2', idx, 'R', R_int, 'name', [name '_m']);
        end
        
        function connectToZone(obj, otherZone, R_between, name)
            if nargin<4, name = sprintf('%s_to_%s', obj.name, otherZone.name); end
            
            % Define the resistor struct
            r = struct('n1', struct('zone', obj, 'idx', 1), 'n2', struct('zone', otherZone, 'idx', 1), 'R', R_between, 'name', name);
            
            % Append the connection to both zones.
            obj.crossRes{end+1} = r;
            otherZone.crossRes{end+1} = r;
        end
        
        function connectToExternalSource(obj, hf, nodeName)
            % connectToExternalSource(hf, 'NodeName')
            % hf is function handle: hf(building) -> heat in Watts
            % nodeName is the name of the target node (e.g., 'T_main', 'IntMass1')
            
            % Default to the main node if no name is provided
            if nargin < 3, nodeName = 'T_main'; end
            
            % Check if the node exists in this zone
            if ~ismember(nodeName, {obj.nodes.name})
                error('Node "%s" does not exist in Zone "%s".', nodeName, obj.name);
            end

            obj.heatSources(end+1) = struct('hf', hf, 'nodeName', nodeName);
        end
        
        function T = getMainTemp(obj)
            T = obj.nodes(1).T;
        end
        
        function nodeCount = getNodeCount(obj)
            nodeCount = numel(obj.nodes);
        end
        
        function [A_local, b_local, nodeIndexMap] = assembleLocalLinear(obj, globalIndexBase, nodeGlobalMap)
            % Assemble local contributions for nodes internal to this zone.
            % Returns A_local (n x n diagonal capacities), b_local initial (n x1),
            % nodeIndexMap mapping local idx->global idx
            n = numel(obj.nodes);
            nodeIndexMap = zeros(n,1);
            for i=1:n
                % global index: either provided map or base+local
                if nargin>=3 && ~isempty(nodeGlobalMap)
                    key = sprintf('%s.%s', obj.storey.name, obj.name);
                    % nodeGlobalMap is built in Simulation; here assume nodes are already mapped
                    nodeIndexMap(i) = nodeGlobalMap(sprintf('%s.%s.%s', obj.storey.name, obj.name, obj.nodes(i).name));
                else
                    nodeIndexMap(i) = globalIndexBase + i - 1;
                end
            end
            % A_local will be processed by Simulation directly; this function is a helper stub
            A_local = [];
            b_local = [];
        end
    end
end