%{
----------------------------------------------------------------------------

This file is part of the Sanworks Bpod repository
Copyright (C) 2021 Sanworks LLC, Rochester, New York, USA

----------------------------------------------------------------------------

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, version 3.

This program is distributed  WITHOUT ANY WARRANTY and without even the
implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
%}

% Adapted by Lena Gschossmann 09 March 2023

% Based on the TCPCom.m file
% Wraps the PsychToolbox PNET class for communication with processes
% on the same machine, or on the local network. It inherits read/write syntax
% from the Sanworks ArCOM class: https://github.com/sanworks/ArCOM

classdef UDPCom < handle

    properties
        UDPobj
        Port
        IPAddress
        NetworkRole
        validDataTypes
        OSCAddressPattern
    end

    properties (Access = private)
        IP
        SourcePort
        Socket
        InBuffer
        InBufferBytesAvailable
        Time2WaitForClient = 10; % Seconds to wait for a client
        Timeout = 3;
        IPaddress
        IsLittleEndian
    end

    methods

        function obj = UDPCom(port, varargin)
            IP = 'localhost';
            obj.Socket = -1;
            args = lower(varargin{1});
            switch args
                case 'server'
                    obj.NetworkRole = 'Server';
                    Port = port;
                case 'client'
                    obj.NetworkRole = 'Client';
                    SourcePort = varargin{2};
                    Port = port;
            end
            obj.UDPobj = [];
            obj.InBuffer = [];
            obj.InBufferBytesAvailable = 0;
            obj.validDataTypes = {'char', 'uint8', 'uint16', 'uint32', 'uint64', 'int8', 'int16', 'int32', 'int64', 'single', 'double'};
            
            switch obj.NetworkRole
                case 'Server'
                    obj.Socket = pnet('udpsocket',Port); % Sets up Udp server
                    stat = pnet(obj.Socket, 'status');
                case 'Client'
                    obj.Socket = pnet('udpsocket',SourcePort); % Sets up Udp client
                    pnet(obj.Socket,'udpconnect',IP,Port);
                    stat = pnet(obj.Socket,'status');
            end

            if obj.Socket == -1
                error('UDPCom: Error creating socket on localhost.');
            elseif stat == 0
                error(['UDPCom: Could not connect to socket at ' IP ' on port ' num2str(Port)])
            else
                obj.UDPobj = obj.Socket;
                disp(['UDPCom: Connection established on port ' num2str(Port) '- ' obj.NetworkRole])
            end

            pause(.1);
            pnet(obj.UDPobj,'setwritetimeout',obj.Timeout);
            pnet(obj.UDPobj,'setreadtimeout',obj.Timeout);
            obj.IPAddress = IP;
            obj.Port = Port;

            switch obj.NetworkRole
                case 'Server'
                    obj.IsLittleEndian = [];
                    obj.OSCAddressPattern = [];
                case 'Client'
                    % Check if system uses little endian (for int/float conversion)
                    [~, ~, endian] = computer;
                    obj.IsLittleEndian = endian == 'L';
                    % Define OSC address pattern
                    obj.OSCAddressPattern = '\Bpod';
                    obj.OSCAddressPattern = [uint8(char(obj.OSCAddressPattern)) 0 0 0 0];
                    obj.OSCAddressPattern = obj.OSCAddressPattern(1:end-mod(length(obj.OSCAddressPattern),4));
            end
        end

        function bytesAvailable = bytesAvailable(obj)
            obj.assertConn; % Assert that connection is still active, and attempt to renew if not
            packetsize = pnet(obj.UDPobj,'readpacket');
            bytesAvailable = length(pnet(obj.UDPobj,'read', packetsize, 'uint8', 'native','view', 'noblock')) + obj.InBufferBytesAvailable;
        end

        function write(obj, varargin) % Arguments: data and its respective type in alternating manner
            obj.assertConn; % Assert that connection is still active, and attempt to renew if not

            if nargin == 2 % Single array with no data type specified (defaults to uint8)
                nArrays = 1;
                data2Send = varargin(1);
                dataTypes = {'uint8'};
            else
                nArrays = (nargin-1)/2;
                data2Send = varargin(1:2:end);
                dataTypes = varargin(2:2:end);
            end
            nTotalBytes = 0;
            DataLength = cellfun('length',data2Send);
            for i = 1:nArrays
                switch dataTypes{i}
                    case 'char'
                        DataLength(i) = DataLength(i)-mod(DataLength(i)+4,4);
                    case 'uint16'
                        DataLength(i) = DataLength(i)*2;
                    case 'uint32'
                        DataLength(i) = DataLength(i)*4;
                    case 'uint64'
                        DataLength(i) = DataLength(i)*8;
                    case 'int16'
                        DataLength(i) = DataLength(i)*2;
                    case 'int32'
                        DataLength(i) = DataLength(i)*4;
                    case 'int64'
                        DataLength(i) = DataLength(i)*8;
                    case 'single'
                        DataLength(i) = DataLength(i)*4;
                    case 'double'
                        DataLength(i) = DataLength(i)*8;
                end
                nTotalBytes = nTotalBytes + DataLength(i);
            end
            ByteStringPos = 1;
            ByteString = uint8(zeros(1,nTotalBytes));
            for i = 1:nArrays
                dataType = dataTypes{i};
                data = data2Send{i};
                switch dataType % Check range and cast to uint8
                    case 'char'
                        data = [uint8(char(data)) 0 0 0 0];
                        ByteString(ByteStringPos:ByteStringPos+DataLength(i)-1) = data(1:DataLength(i));
                    case 'uint8'
                        if obj.IsLittleEndian, ByteString(ByteStringPos:ByteStringPos+DataLength(i)-1) = swapbytes(uint8(data));
                        else, ByteString(ByteStringPos:ByteStringPos+DataLength(i)-1) = uint8(data);
                        end
                    case 'uint16'
                        if obj.IsLittleEndian, ByteString(ByteStringPos:ByteStringPos+DataLength(i)-1) = typecast(swapbytes(uint16(data), 'uint8'));
                        else ,ByteString(ByteStringPos:ByteStringPos+DataLength(i)-1) = typecast(uint16(data), 'uint8');
                        end
                    case 'uint32'
                        if obj.IsLittleEndian, ByteString(ByteStringPos:ByteStringPos+DataLength(i)-1) = typecast(uint32(data), 'uint8');
                        else, obj.IsLittleEndian, ByteString(ByteStringPos:ByteStringPos+DataLength(i)-1) = typecast(swapbytes(uint32(data), 'uint8'));
                        end
                    case 'uint64'
                        if obj.IsLittleEndian, ByteString(ByteStringPos:ByteStringPos+DataLength(i)-1) = typecast(swapbytes(uint64(data), 'uint8'));
                        else, ByteString(ByteStringPos:ByteStringPos+DataLength(i)-1) = typecast(uint64(data), 'uint8');
                        end
                    case 'int8'
                        if obj.IsLittleEndian, ByteString(ByteStringPos:ByteStringPos+DataLength(i)-1) = typecast(swapbytes(int8(data), 'uint8'));
                        else, ByteString(ByteStringPos:ByteStringPos+DataLength(i)-1) = typecast(int8(data), 'uint8');
                        end
                    case 'int16'
                        if obj.IsLittleEndian, ByteString(ByteStringPos:ByteStringPos+DataLength(i)-1) = typecast(swapbytes(int16(data), 'uint8'));
                        else, ByteString(ByteStringPos:ByteStringPos+DataLength(i)-1) = typecast(int16(data), 'uint8');
                        end
                    case 'int32'
                        if obj.IsLittleEndian, ByteString(ByteStringPos:ByteStringPos+DataLength(i)-1) = typecast(swapbytes(int32(data), 'uint8'));
                        else, ByteString(ByteStringPos:ByteStringPos+DataLength(i)-1) = typecast(int32(data), 'uint8');
                        end
                    case 'int64'
                        if obj.IsLittleEndian, ByteString(ByteStringPos:ByteStringPos+DataLength(i)-1) = typecast(swapbytes(int64(data), 'uint8'));
                            else, ByteString(ByteStringPos:ByteStringPos+DataLength(i)-1) = typecast(int64(data), 'uint8');
                        end
                    case 'single'
                        if obj.IsLittleEndian, ByteString(ByteStringPos:ByteStringPos+DataLength(i)-1) = typecast(swapbytes(single(data), 'uint8'));
                            else, ByteString(ByteStringPos:ByteStringPos+DataLength(i)-1) = typecast(single(data), 'uint8');
                        end
                    case 'double'
                        if obj.IsLittleEndian, ByteString(ByteStringPos:ByteStringPos+DataLength(i)-1) = typecast(swapbytes(double(data), 'uint8'));
                            else, ByteString(ByteStringPos:ByteStringPos+DataLength(i)-1) = typecast(double(data), 'uint8');
                        end
                    otherwise
                        error(['Error: Data type: ' dataType ' not supported by PythonLink'])
                end
                ByteStringPos = ByteStringPos + DataLength(i);
            end
            
            % Add type of data send via OSC
            ByteType = [',i' 0 0 0 0];
            ByteType = ByteType(1:end-mod(length(ByteType),4));

            OSCPacket = [obj.OSCAddressPattern, ByteType, ByteString];
            pnet(obj.UDPobj,'write', OSCPacket);
            pnet(obj.UDPobj, 'writepacket');
        end

        function varargout = read(obj, varargin) % Arguments: data to be read and its respective type in alternating manner
            obj.assertConn; % Assert that connection is still active, and attempt to renew if not
            if nargin == 2
                nArrays = 1;
                nValues = varargin(1);
                dataTypes = {'uint8'};
            else
                nArrays = (nargin-1)/2;
                nValues = varargin(1:2:end);
                dataTypes = varargin(2:2:end);
            end
            nValues = double(cell2mat(nValues));
            nTotalBytes = 0;
            for i = 1:nArrays
                switch dataTypes{i}
                    case {'char', 'uint8', 'int8'}
                        nTotalBytes = nTotalBytes + nValues(i);
                    case {'uint16','int16'}
                        nTotalBytes = nTotalBytes + nValues(i)*2;
                    case {'uint32','int32','single'}
                        nTotalBytes = nTotalBytes + nValues(i)*4;
                    case {'uint64','int64','double'}
                        nTotalBytes = nTotalBytes + nValues(i)*8;
                end
            end
            StartTime = now*100000;
            while nTotalBytes > obj.InBufferBytesAvailable && ((now*100000)-StartTime < obj.Timeout)
                packetsize = pnet(obj.UDPobj,'readpacket');
                nBytesAvailable = length(pnet(obj.UDPobj,'read', packetsize, 'uint8', 'native','view', 'noblock'));
                if nBytesAvailable > 0
                    obj.InBuffer = [obj.InBuffer uint8(pnet(obj.UDPobj,'read', nBytesAvailable, 'uint8'))];
                end
                obj.InBufferBytesAvailable = obj.InBufferBytesAvailable + nBytesAvailable;
            end
            
            if nTotalBytes > obj.InBufferBytesAvailable
                error('Error: The UDP port did not return the requested number of bytes.')
            end
            Pos = 1;
            varargout = cell(1,nArrays);
            for i = 1:nArrays
                switch dataTypes{i}
                    case 'char'
                        nBytesRead = nValues(i);
                        varargout{i} = char(obj.InBuffer(1:nBytesRead));
                    case 'uint8'
                        nBytesRead = nValues(i);
                        varargout{i} = uint8(obj.InBuffer(1:nBytesRead));
                    case 'uint16'
                        nBytesRead = nValues(i)*2;
                        varargout{i} = typecast(uint8(obj.InBuffer(1:nBytesRead)), 'uint16');
                    case 'uint32'
                        nBytesRead = nValues(i)*4;
                        varargout{i} = typecast(uint8(obj.InBuffer(1:nBytesRead)), 'uint32');
                    case 'uint64'
                        nBytesRead = nValues(i)*8;
                        varargout{i} = typecast(uint8(obj.InBuffer(1:nBytesRead)), 'uint64');
                    case 'int8'
                        nBytesRead = nValues(i);
                        varargout{i} = typecast(uint8(obj.InBuffer(1:nBytesRead)), 'int8');
                    case 'int16'
                        nBytesRead = nValues(i)*2;
                        varargout{i} = typecast(uint8(obj.InBuffer(1:nBytesRead)), 'int16');
                    case 'int32'
                        nBytesRead = nValues(i)*4;
                        varargout{i} = typecast(uint8(obj.InBuffer(1:nBytesRead)), 'int32');
                    case 'int64'
                        nBytesRead = nValues(i)*8;
                        varargout{i} = typecast(uint8(obj.InBuffer(1:nBytesRead)), 'int64');
                    case 'single'
                        nBytesRead = nValues(i)*4;
                        varargout{i} = typecast(uint8(obj.InBuffer(1:nBytesRead)), 'single');
                    case 'double'
                        nBytesRead = nValues(i)*8;
                        varargout{i} = typecast(uint8(obj.InBuffer(1:nBytesRead)), 'double');
                end
                Pos = Pos + nBytesRead;
                obj.InBuffer = obj.InBuffer(nBytesRead+1:end);
                obj.InBufferBytesAvailable = obj.InBufferBytesAvailable - nBytesRead;
            end
        end

        function renew(obj) % Disconnect and renew connection
            if obj.UDPobj ~= -1
                pnet(obj.UDPobj,'close');
            end
            switch obj.NetworkRole
                case 'Server'
                    disp('Server: Connection dropped. Attempting to reconnect...');
                    obj.Socket=pnet('udpsocket',obj.Port);
                    if obj.Socket == -1
                        error(['UDPCom: Could not connect to port ' num2str(obj.Port)]);
                    else
                        obj.UDPobj = obj.Socket;
                    end

                case 'Client'
                    disp('Client: Connection dropped. Attempting to reconnect...');
                    obj.Socket = pnet('udpsocket',obj.SourcePort); % Sets up Udp client
                    pnet(obj.Socket,'udpconnect',obj.IP,obj.Port);
                    if obj.Socket == -1
                        error(['UDPCom: Could not connect to port ' num2str(obj.Port)]);
                    else
                        obj.UDPobj = obj.Socket;
                    end
            end
            pnet(obj.UDPobj,'setwritetimeout',obj.Timeout);
            pnet(obj.UDPobj,'setreadtimeout',obj.Timeout);
            disp('REMOTE HOST RECONNECTED');
        end

        function assertConn(obj)
            pnet(obj.UDPobj,'read', 1, 'uint8', 'native','view', 'noblock'); % Peek at first byte available. If connection is broken, this updates pnet 'status'
            status = pnet(obj.UDPobj, 'status');
            if status < 1
                obj.renew;
            end
        end

        function delete(obj)
            if obj.UDPobj ~= -1
                pnet(obj.UDPobj,'close'); 
            end
        end
    end
end
