function varargout = process_nst_detect_bad( varargin )

% @=============================================================================
% This function is part of the Brainstorm software:
% http://neuroimage.usc.edu/brainstorm
% 
% Copyright (c)2000-2016 University of Southern California & McGill University
% This software is distributed under the terms of the GNU General Public License
% as published by the Free Software Foundation. Further details on the GPLv3
% license can be found at http://www.gnu.org/copyleft/gpl.html.
% 
% FOR RESEARCH PURPOSES ONLY. THE SOFTWARE IS PROVIDED "AS IS," AND THE
% UNIVERSITY OF SOUTHERN CALIFORNIA AND ITS COLLABORATORS DO NOT MAKE ANY
% WARRANTY, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO WARRANTIES OF
% MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE, NOR DO THEY ASSUME ANY
% LIABILITY OR RESPONSIBILITY FOR THE USE OF THIS SOFTWARE.
%
% For more information type "brainstorm license" at command prompt.
% =============================================================================@
%
% Authors: Thomas Vincent, 2015-2019

%TODO: output map of bad channels

eval(macro_method);
end


%% ===== GET DESCRIPTION =====
function sProcess = GetDescription() %#ok<DEFNU>
    % Description the process
    %TOCHECK: how do we limit the input file types (only NIRS data)?
    sProcess.Comment     = 'Detect bad channels';
    sProcess.FileTag     = '';
    sProcess.Category    = 'Custom';
    sProcess.SubGroup    = 'NIRS';
    sProcess.Index       = 1003; %0: not shown, >0: defines place in the list of processes
    sProcess.Description = 'http://neuroimage.usc.edu/brainstorm/Tutorials/NIRSFingerTapping#Bad_channel_tagging';
    % sProcess.isSeparator = 0; % add a horizontal bar after the process in
    %                             the list
    % Definition of the input accepted by this process
    sProcess.InputTypes  = {'data', 'raw'};
    % Definition of the outputs of this process
    sProcess.OutputTypes = {'data', 'raw'};
    sProcess.nInputs     = 1;
    sProcess.nMinFiles   = 1;
    % Definition of the options
    sProcess.options.option_remove_negative.Comment = 'Remove negative channels';
    sProcess.options.option_remove_negative.Type    = 'checkbox';
    sProcess.options.option_remove_negative.Value   = 1;
          
    sProcess.options.option_invalidate_paired_channels.Comment = 'Also remove paired channels';
    sProcess.options.option_invalidate_paired_channels.Type    = 'checkbox';
    sProcess.options.option_invalidate_paired_channels.Value   = 1;
    
    sProcess.options.option_max_sat_prop.Comment = 'Maximum proportion of saturating points';
    sProcess.options.option_max_sat_prop.Type    = 'value';
    sProcess.options.option_max_sat_prop.Value   = {1, '', 2};
    
    sProcess.options.option_min_sat_prop.Comment = 'Maximum proportion of flooring points';
    sProcess.options.option_min_sat_prop.Type    = 'value';
    sProcess.options.option_min_sat_prop.Value   = {1, '', 2};
    
    sProcess.options.option_min_separation.Comment = 'Minimum separation';
    sProcess.options.option_min_separation.Type    = 'value';
    sProcess.options.option_min_separation.Value   = {-1, 'cm', 2};
    
    sProcess.options.option_max_separation.Comment = 'Maximum separation';
    sProcess.options.option_max_separation.Type    = 'value';
    sProcess.options.option_max_separation.Value   = {-1, 'cm', 2};
    
    %TODO: scalp contact index and outlier detection mentioned by Zhengchen.
end

%% ===== FORMAT COMMENT =====
function Comment = FormatComment(sProcess) %#ok<DEFNU>
    Comment = sProcess.Comment;
end

%% ===== RUN =====
function OutputFiles = Run(sProcess, sInputs) %#ok<DEFNU>
    
    % Get option values   
    do_remove_neg_channels = sProcess.options.option_remove_negative.Value;
    invalidate_paired_channels = sProcess.options.option_invalidate_paired_channels.Value;
    max_sat_prop = sProcess.options.option_max_sat_prop.Value{1};
    min_sat_prop = sProcess.options.option_min_sat_prop.Value{1};
    max_separation_cm = sProcess.options.option_max_separation.Value{1};
    min_separation_cm = sProcess.options.option_min_separation.Value{1};

    nirs_data_full = in_bst(sInputs.FileName, [], 1, 0, 'no');
    channels = in_bst_channel(sInputs.ChannelFile);
    [nirs_ichans, tmp] = channel_find(channels.Channel, 'NIRS');
    nirs_chan_flags = zeros(size(nirs_data_full.ChannelFlag));
    nirs_chan_flags(nirs_ichans) = 1;
    [new_ChannelFlag, bad_chan_names] = Compute(nirs_data_full.F', channels, ...
                                                nirs_data_full.ChannelFlag, ...
                                                do_remove_neg_channels, max_sat_prop, ...
                                                min_sat_prop, max_separation_cm, min_separation_cm, ...
                                                invalidate_paired_channels, ...
                                                nirs_chan_flags);
    
    % Add bad channels
    tree_set_channelflag({sInputs.FileName}, 'AddBad', bad_chan_names);
    OutputFiles = {sInputs.FileName};
end


%% ===== Compute =====
function [channel_flags, removed_channel_names] = ...
    Compute(nirs_sig, channel_def, channel_flags, do_remove_neg_channels, ...
            max_sat_prop, min_sat_prop, max_separation_cm, min_separation_cm, ...
            invalidate_paired_channels, nirs_chan_flags)
%% Update the given channel flags to indicate which pairs are to be removed:
%% - negative values
%% - saturating
%% - too long or too short separation
%
% Args
%    - nirs_sig: matrix of double, size: time x nb_channels 
%        nirs signals to be filtered
%    - channel_def: struct
%        Defintion of channels as given by brainstorm
%        Used fields: Nirs.Wavelengths, Channel
%    - channels_flags: array of int, size: nb_channels
%        channel flags to update (1 is good, 0 is bad)
%   [- do_remove_neg_channels: boolean], default: 1
%        actually remove pair where at least one channel has negative
%        values
%   [- max_sat_prop: double between 0 and 1], default: 1
%        maximum proportion of saturating values.
%        If 1 then all time series can be saturating -> ignore
%        If 0.2 then if more than 20% of values are equal to the max
%        the pair is discarded.
%   [- min_sat_prop: double between 0 and 1], default: 1
%        maximum proportion of flooring values.
%        If 1 then all time series can be flooring (equal to lowest value) -> ignore
%        If 0.2 then if more than 20% of values are equal to the min value
%        the pair is discarded.
%   [- max_separation_cm: positive double], default: 10
%        maximum optode separation in cm.
%   [- min_separation_cm: positive double], default: 0
%        minimum optode separation in cm.
%   [- invalidate_paired_channels: int, default: 1]
%        When a channel is tagged as bad, also remove the other paired 
%        channels
%   [- nirs_chan_flags: array of bool, default: ones(nb_channels, 1)]
%        Treat only channels where flag is 1. Used to avoid treating
%        auxiliary channels for example.
%  
% Output:
%    - channel_flags: array of int, size: nb_channels
%    - bad_channel_names: cell array of str, size: nb of bad channels
%
% TODO: test arg nirs_chan_flags. When there are neg values in AUX chan,
%       it should not be filtered
%  

    prev_channel_flags = channel_flags;
    if nargin < 4
        do_remove_neg_channels = 1;
    end
    if nargin < 5
        max_sat_prop = 1;
    end
    
    if nargin < 6
        min_sat_prop = 1;
    end
    
    if nargin < 7
        max_separation_cm = -1;
    end
    
    if nargin < 8
        min_separation_cm = -1;
    end
    
    if nargin < 9
        invalidate_paired_channels = 1;
    end
    
    if nargin < 10
        nirs_chan_flags = ones(size(channel_flags));
    end 
    
    max_separation_m = max_separation_cm / 100;
    min_separation_m = min_separation_cm / 100;
    
    if do_remove_neg_channels
        neg_channels = any(nirs_sig < 0, 1);
        channel_flags(neg_channels) = -1;
    end
    
    if max_sat_prop < 1
        ceiling = nirs_sig == repmat(max(nirs_sig, [], 1), ...
                                        size(nirs_sig, 1), 1);
        prop_sat_ceil = sum(ceiling, 1) / size(nirs_sig, 1);
        channel_flags(prop_sat_ceil >= max_sat_prop) = -1;
    end
    
    if min_sat_prop < 1
        flooring = nirs_sig == repmat(min(nirs_sig, [], 1), ...
                                        size(nirs_sig, 1), 1);
        prop_sat_floor = sum(flooring, 1) / size(nirs_sig, 1);
        channel_flags(prop_sat_floor >= min_sat_prop) = -1;
    end

    separations_m_by_chans = process_nst_separations('Compute', channel_def.Channel);

    if min_separation_m > 0
        channel_flags(separations_m_by_chans <= min_separation_m) = -1;
    end

    if max_separation_m > 0
        channel_flags(separations_m_by_chans >= max_separation_m) = -1;
    end
    
    if invalidate_paired_channels
        channel_flags(~nirs_chan_flags) = 0; %chans to ignore, can be unpaired
        channel_flags = fix_chan_flags_wrt_pairs(channel_def.Channel, ...
                                                 channel_def.Nirs.Wavelengths, ...
                                                 channel_flags * -1) * -1;
    end
    
    channel_flags(~nirs_chan_flags) = -1;
    removed =  (prev_channel_flags ~= -1 & channel_flags == -1);
    removed_channel_names = {channel_def.Channel(removed).Name};
end

function fixed_chan_flags = fix_chan_flags_wrt_pairs(channel_def, wls, chan_flags)
% Make flags consistent: if flag of a channel is 1, set to 1 all channels
% involved in the same pair

fixed_chan_flags = chan_flags;
nb_wavelengths = length(wls);
nb_channels = length(channel_def);
ichan_to_scan = find(chan_flags==1);
for ii=1:length(ichan_to_scan)
    ichan = ichan_to_scan(ii);
    chan_name = channel_def(ichan).Name;
    pair_prefix = chan_name(1:strfind(chan_name, 'WL'));
    nb_fixed_chans = 0;
    search = {ichan+1:nb_channels ; 1:ichan-1};
    for isearch=1:length(search)
        for i_other_chan=search{isearch}
            if ~isempty(strfind(channel_def(i_other_chan).Name, pair_prefix))
                fixed_chan_flags(i_other_chan) = 1;
                nb_fixed_chans = nb_fixed_chans + 1;
            end
            if nb_fixed_chans == nb_wavelengths-1
                break;
            end
        end
        if nb_fixed_chans == nb_wavelengths-1
            break;
        end
    end
    if nb_fixed_chans ~= nb_wavelengths-1
        throw(MException('NSTError:InconsistentChannel', ...
                         ['Channels paired to ' chan_name ' were not all flagged']));
    end
end
end
