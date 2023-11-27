function data = packosc(path,varargin)
% This is adapted from code written by Mark,
% available on:
% https://www.mathworks.com/matlabcentral/fileexchange/31400-send-open-sound-control-osc-messages
% It was changed such that it only returns a message packed as osc but does
% not write into a file

    %figure out little endian for int/float conversion
    [~, ~, endian] = computer;
    littleEndian = endian == 'L';

    % set type
    if nargin >= 1,
        types = oscstr([',' varargin{1}]);
    else
        types = oscstr(',');
    end;
    
    % set args (either a matrix, or varargin)
    if nargin == 2 && length(types) > 2
        args = varargin{2};
    else
        args = varargin(2:end);
    end;

    % convert arguments to the right bytes
    data = [];
    for i=1:length(args)
        switch(types(i+1))
            case 'i'
                data = [data oscint(args{i},littleEndian)];
            case 'f'
                data = [data oscfloat(args{i},littleEndian)];
            case 's'
                data = [data oscstr(args{i})];
            case 'B'
                if args{i}
                    types(i+1) = 'T';
                else
                    types(i+1) = 'F';
                end;
            case {'N','I','T','F'}
                %ignore data
            otherwise
                warning(['Unsupported type: ' types(i+1)]);
        end;
    end;
    
    %write data to UDP
    data = [oscstr(path) types data];
end

%Conversion from double to float
function float = oscfloat(float,littleEndian)
   if littleEndian
        float = typecast(swapbytes(single(float)),'uint8');
   else
        float = typecast(single(float),'uint8');
   end;
end

%Conversion to int
function int = oscint(int,littleEndian)
   if littleEndian
        int = typecast(swapbytes(int32(int)),'uint8');
   else
        int = typecast(int32(int),'uint8');
   end;
end

%Conversion to string (null-terminated, in multiples of 4 bytes)
function string = oscstr(string)
    string = [string 0 0 0 0];
    string = string(1:end-mod(length(string),4));
end