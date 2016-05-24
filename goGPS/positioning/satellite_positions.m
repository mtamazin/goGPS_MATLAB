function [XS, dtS, XS_tx, VS_tx, time_tx, no_eph, eclipsed, sys_idx] = satellite_positions(time_rx, pseudorange, sat, Eph, SP3, sbas, err_tropo, err_iono, dtR, frequencies, obs_comb)

% SYNTAX:
%   [XS, dtS, XS_tx, VS_tx, time_tx, no_eph, eclipsed, sys_idx] = satellite_positions(time_rx, pseudorange, sat, Eph, SP3, sbas, err_tropo, err_iono, dtR, frequencies, obs_comb);
%
% INPUT:
%   time_rx     = reception time
%   pseudorange = observed code pseudoranges
%   sat         = available satellite indexes
%   Eph         = ephemeris
%   SP3         = structure containing precise ephemeris data
%   sbas        = SBAS corrections
%   err_tropo   = tropospheric delays
%   err_iono    = ionospheric delays
%   dtR         = receiver clock offset
%   frequencies = L1 carrier (phase=1), L2 carrier (phase=2)
%   obs_comb    = observations combination (e.g. iono-free: obs_comb = 'IONO_FREE')
%
% OUTPUT:
%   XS      = satellite position at transmission time in ECEF(time_rx) (X,Y,Z)
%   dtS     = satellite clock error (vector)
%   XS_tx   = satellite position at transmission time in ECEF(time_tx) (X,Y,Z)
%   VS_tx   = satellite velocity at transmission time in ECEF(time_tx) (X,Y,Z)
%   time_tx = transmission time (vector)
%   no_eph   = satellites with no ephemeris available (vector) (0: available, 1: not available)
%   eclipsed = satellites under eclipse condition (vector) (0: OK, 1: eclipsed)
%   sys_idx  = array with different values for different systems
%
% DESCRIPTION:

%----------------------------------------------------------------------------------------------
%                           goGPS v0.4.3
%
% Copyright (C) 2009-2014 Mirko Reguzzoni, Eugenio Realini
%----------------------------------------------------------------------------------------------
%
%    This program is free software: you can redistribute it and/or modify
%    it under the terms of the GNU General Public License as published by
%    the Free Software Foundation, either version 3 of the License, or
%    (at your option) any later version.
%
%    This program is distributed in the hope that it will be useful,
%    but WITHOUT ANY WARRANTY; without even the implied warranty of
%    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%    GNU General Public License for more details.
%
%    You should have received a copy of the GNU General Public License
%    along with this program.  If not, see <http://www.gnu.org/licenses/>.
%----------------------------------------------------------------------------------------------

nsat = length(sat);

time_tx = zeros(nsat,1);
dtS     = zeros(nsat,1);
XS      = zeros(nsat,3);
XS_tx   = zeros(nsat,3);
VS_tx   = zeros(nsat,3);

%satellites with no ephemeris available
no_eph  = zeros(nsat,1);

%satellites under eclipse condition
eclipsed  = zeros(nsat,1);

%system array
sys_idx = zeros(nsat,1);

for i = 1 : nsat
    
    k = find_eph(Eph, sat(i), time_rx);
    
    if (isempty(k) & isempty(SP3))
        no_eph(i) = 1;
        continue
    end
    
    %compute signal transmission time
    [time_tx(i,1), dtS(i,1)] = transmission_time(time_rx, pseudorange(i), sat(i), Eph(:,k), SP3, sbas, err_tropo(i), err_iono(i), dtR, frequencies, obs_comb);

    if (isempty(time_tx(i,1)) || isnan(time_tx(i,1)))
        no_eph(i) = 1;
        continue
    end
    
    if (isempty(SP3))
        
        %compute satellite position and velocity at transmission time
        [XS_tx(i,:), VS_tx(i,:)] = satellite_orbits(time_tx(i,1), Eph(:,k), sat(i), sbas);
        
        %detect satellite constellation
        sys = Eph(31,k);
    else
        
        %interpolate SP3 coordinates at transmission time
        [XS_tx(i,:), VS_tx(i,:)] = interpolate_SP3_coord(time_tx(i,1), SP3, sat(i));
        
        %relativistic correction term
        dtrel = relativistic_clock_error_correction(time_tx(i,1), Eph, XS_tx(i,:), VS_tx(i,:));
        time_tx(i,1) = time_tx(i,1) - dtrel;
        dtS(i,1) = dtS(i,1) + dtrel;

        %group delay correction term
        if (nargin > 9 && ~strcmp(obs_comb,'IONO_FREE'))
            gamma = (goGNSS.F1/goGNSS.F2)^2;
            tgd = 1/(1-gamma)*SP3.DCB.P1P2.value(sat(i),1)*1e-9;
            if (length(frequencies) == 2)
                time_tx(i,1) = time_tx(i,1) + tgd;
                dtS(i,1) = dtS(i,1) - tgd;
                %dtS(i,2) = dtS(i,1) - gamma*tgd; <--- TO BE DONE!
            else
                if (frequencies(1) == 1)
                    time_tx(i,1) = time_tx(i,1) + tgd;
                    dtS(i,1) = dtS(i,1) - tgd;
                else
                    time_tx(i,1) = time_tx(i,1) + gamma*tgd;
                    dtS(i,1) = dtS(i,1) - gamma*tgd;
                end
            end
        end
        
        %second iteration for taking into account the relativistic effect and group delay corrections
        [XS_tx(i,:), VS_tx(i,:)] = interpolate_SP3_coord(time_tx(i,1), SP3, sat(i));
        
        %detect satellite constellation
        sys = SP3.sys(sat(i));
    end
    
    %computation of ECEF satellite position at time_rx
    traveltime = time_rx - time_tx(i,1);
    switch char(sys)
        case 'G'
            Omegae_dot = goGNSS.OMEGAE_DOT_GPS; sys_idx(i,1) = 1;
        case 'R'
            Omegae_dot = goGNSS.OMEGAE_DOT_GLO; sys_idx(i,1) = 2;
        case 'E'
            Omegae_dot = goGNSS.OMEGAE_DOT_GAL; sys_idx(i,1) = 3;
        case 'C'
            Omegae_dot = goGNSS.OMEGAE_DOT_BDS; sys_idx(i,1) = 4;
        case 'J'
            Omegae_dot = goGNSS.OMEGAE_DOT_QZS; sys_idx(i,1) = 5;
        otherwise
            fprintf('Something went wrong in satellite_positions.m\nUnrecognized Satellite system!\n');
            Omegae_dot = goGNSS.OMEGAE_DOT_GPS;
    end
    XS(i,:) = earth_rotation_correction(traveltime, XS_tx(i,:), Omegae_dot);
    
    if (~isempty(SP3))
        %check eclipse condition
        eclipsed(i,1) = check_eclipse_condition(time_rx, XS(i,:), SP3, sat(i));
    end
end