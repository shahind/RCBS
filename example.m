B = RCBS.Building();
B.addStorey('Storey1');
B.addStorey('Storey2');

B.Storey1.addZone('Zone1', 'C_main', 2e6);
B.Storey1.addZone('Zone2', 'C_main', 2e6);
B.Storey1.addZone('Zone3', 'C_main', 2e6);
B.Storey2.addZone('Zone4', 'C_main', 2e6);

B.Storey1.Zone1.addWall(2.5, 2e7, 20, 'Wall');    % R = 2.5 K/W (Good insulator)
B.Storey1.Zone1.addWindow(0.5, 'Window');         % R = 0.5 K/W (A decent window)
B.Storey1.Zone1.addInternalMass(1e-4, 5e7, 20, 'IntMass'); 

B.Storey1.Zone2.addWall(2.5, 2e7, 20, 'Wall');    % R = 2.5 K/W (Good insulator)
B.Storey1.Zone2.addWindow(0.5, 'Window');         % R = 0.5 K/W (A decent window)
B.Storey1.Zone2.addInternalMass(1e-4, 5e7, 20, 'IntMass'); 

B.Storey1.Zone3.addWall(2.5, 2e7, 20, 'Wall');    % R = 2.5 K/W (Good insulator)
B.Storey1.Zone3.addWindow(0.5, 'Window');         % R = 0.5 K/W (A decent window)
B.Storey1.Zone3.addInternalMass(1e-4, 5e7, 20, 'IntMass'); 

B.Storey2.Zone4.addWall(2.5, 2e7, 20, 'Wall');    % R = 2.5 K/W (Good insulator)
B.Storey2.Zone4.addRoof(2.5, 2e7, 20, 'Roof');    % R = 0.5 K/W (A decent window)
B.Storey2.Zone4.addInternalMass(1e-4, 5e7, 20, 'IntMass'); 

B.Storey1.Zone1.connectToZone(B.Storey1.Zone2, 5.0, 'Z1toZ2');
B.Storey1.Zone2.connectToZone(B.Storey1.Zone3, 5.0, 'Z2toZ3');
B.Storey1.Zone2.connectToZone(B.Storey2.Zone4, 5.0, 'Z2toZ4');

heater = @(Bld) ( (hour(Bld.simulation.t) >=6 && hour(Bld.simulation.t) < 9) * 5000 );
B.Storey1.Zone2.connectToExternalSource(heater, 'IntMass');
B.outdoorTempFunc = @(t) 5 + 10*sin(2*pi*(hour(t) + minute(t)/60)/24);
B.simulation.startDate = datetime(2025,10,1,0,0,0);
B.simulation.timeStep = minutes(10);
B.simulate(days(2));
B.simulation.plotResults();
B.visualize();