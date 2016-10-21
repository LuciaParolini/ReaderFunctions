% A very Basic Matlab interface to the .movie binary files
classdef moviereader_play < handle
    
    % movie properties and data
    properties
        Directory % The subdirectory that contains the video
        Filename  % The filename of the video
        NumFrames % The number of frames contained in the video
        framerate % The number of frames recorded in a second
        width     % The image width, in pixels
        height    % The image height, in pixels
        
        
        
    end
    
    properties (SetAccess=private, Hidden)
        offset_header; % bytes before the data
        version;
        camera_type;
        endian;
        length_data;
        length_header;
        data_depth;
        image_bytes;
        total_bytes;
        length_in_words;
    end
    
    % functions to read and display the movie
    methods
        function movie=moviereader_play(datadir, moviename,varargin)
            % Function that loads the video and initialize its
            % structure, extracting the infos stored into the header of the
            % movie file.
            %
            % USAGE: movie=moviereader(filename);
            %        movie=moviereader(filename,directory);
            %datadir='./';
            if nargin>1
                datadir=varargin{1};
            end 
            if ~strcmp(datadir(end),'/');
                datadir=[datadir, '/'];
            end
            
            movie.Directory=datadir;
            movie.Filename=moviename;
            
            fid=fopen([datadir,moviename],'r');
            % Camera Constants
            % % Finding begining of the frame header need to store the offset
            % % The ASCII part is only stored once, before 1st frame's header
            offset=0;
            word=0;
            
            CAMERA_MOVIE_MAGIC = hex2dec('496d6554'); %'TemI'
            CAMERA_TYPE_IIDC = 1;
            CAMERA_TYPE_ANDOR= 2;
            CAMERA_TYPE_XIMEA= 3;
            
            % % find offset of the first header  store in offset_header
            while ( word ~= CAMERA_MOVIE_MAGIC )
                
                % % is there another word in the file?
                % add is not in a MB stop !!!
                status = fseek( fid, offset, -1 ); % from begining (-1)
                if ( status == -1)
                    fprintf('No Magic word found in all of the file \n');
                    return
                end
                word = fread( fid, 1,'*uint32' ) ;
                offset = offset + 1  ;
                if (offset >= 1000000)
                    fprintf('The potential ASCII header is too long. \n No "TemI" found, bailing out. \n Old data type( pre January 2012) ? \n');
                    return
                end
                % %  If it is magic word note the offset
                if ( word == CAMERA_MOVIE_MAGIC )
                    offset = offset -1 ; % point back to magic
                    fseek( fid, offset, -1 ) ;
                    break;
                end
            end
            
            % This variable is important make sure to keep it for as long as you
            % read from this file - additional offset before first header
            movie.offset_header = offset;
            
            
            % Common stuff for all camera types
            common_info = fread(fid,6,'*uint32'); %read 20 bytes
            movie.version = common_info(2);
            movie.camera_type = common_info(3);
            if (movie.version == 1)
                movie.endian=common_info(4); % BigEndian,16bit==2, LittleEndian,16bit==1, 8bit==1
                movie.length_header = common_info(5);
                movie.length_data = common_info(6);
            elseif (movie.version == 0)
                %need to hardwire BigEndian/LittleEndian
                movie.endian = 2; % BigEndian==2
                movie.length_header = common_info(4) ;
                movie.length_data = common_info(5)  ;
                fseek(fid,-4,'cof') ; % go back one extra word read into the common_info
            end
            
            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%555
            % Camera specific settings
            switch movie.camera_type
                
                %%%%%% IIDC %%%%%%%%
                case CAMERA_TYPE_IIDC
                    fseek( fid, 24, 0 ); % skip next 24 bytes to c_timestamp 44 position
                    if (movie.endian == 2)
                        c_timestamp([2 1],1) = fread(fid,2,'*uint32');
                    else
                        c_timestamp([1 2],1) = fread(fid,2,'*uint32');
                    end
                    if (movie.version == 0)
                        data_shape([1 2 3 4 5 6 7 8]) = fread(fid,8,'*uint32');
                        data_shape(9) = fread(fid,1,'*uint64'); %total data stored
                    elseif (movie.version == 1)
                        data_shape([1 2 3 4 5 6 7 8 9 10]) = fread(fid,10,'*uint32');
                        data_shape(11) = fread(fid,1,'*uint64'); %total data i_total_bytes stored
                    end
                    % columns are:  (v.1 only i_size_x_max; i_size_y_maxc_size_x;) c_size_y; c_pos_x; c_pos_y; c_pixnum; c_stride;
                    % c_data_depth; c_image_bytes; c_total_bytes
                    
                    % go to the c_timestamp in the next header :
                    if (movie.version == 0)
                        % (44 bytes from begining of that header to position before c_timestamp):
                        timestamp_pos = 44;
                    elseif (movie.version == 1)
                        % (48 bytes from begining of that header to position befor c_timestamp):
                        timestamp_pos = 48;
                    end
                    
                    fseek( fid, movie.offset_header + movie.length_header + movie.length_data +timestamp_pos, -1 );
                    if (movie.endian == 2)
                        c_timestamp([2 1],2) = fread(fid,2,'*uint32');
                    else
                        c_timestamp([1 2],2) = fread(fid,2,'*uint32');
                    end
                    
                    movie.framerate = 1/( ( double(c_timestamp(1,2)) - double(c_timestamp(1,1))) /10^6 );  %find out frame rate (f/s)
                    movie.width = data_shape(1);
                    movie.height= data_shape(2);
                    
                    movie.data_depth = data_shape(9);  %this is number of bytes 8 or 16
                    
                    movie.image_bytes = data_shape(10);
                    movie.total_bytes = data_shape(11);
                    
                    if (movie.data_depth == 16)
                        movie.length_in_words = floor(movie.image_bytes/2); %each word is 2 bytes;
                    elseif (movie.data_depth == 8)
                        movie.length_in_words = movie.image_bytes;
                    else
                        fprintf('Bit depth neither 8 not 16 - not programmed for this.\n');
                        return;
                    end
                    
                    %%%%%% ANDOR %%%%%%%%
                case CAMERA_TYPE_ANDOR
                    movie.endian = 1; % LittleEndian==1
                    fprintf('Still not programmed for Andor, get structure of the header from Eileen. \n');
                    return;
                    
                    
                    %%%%%% XIMEA %%%%%%%%
                case CAMERA_TYPE_XIMEA
                    fread(fid,100,'*char'); %camera name... I don't need that, I just skip
                    dim_char=100;
                    fseek( fid, 4, 0 ); % skip next 4 bytes to go to timestamp
                    
                    c_timestamp(1,[1,2]) = fread(fid,2,'*uint64');       % time of the first image
                    
                    if (movie.version == 1)
                        data_shape([1 2 3 4 5 6]) = fread(fid,6,'*uint32');
                        timestamp_pos = 28+dim_char;
                    end
                    
                    fseek( fid, movie.offset_header + movie.length_header + movie.length_data +timestamp_pos, -1 );
                    c_timestamp(2,[1,2]) = fread(fid,2,'*uint64');
                    
                    
                    movie.framerate = 1/( ( double(c_timestamp(2,1)) + double(c_timestamp(2,2))/10^9) - ( double(c_timestamp(1,1)) + double(c_timestamp(1,2))/10^9));  %find out frame rate (f/s)
                    movie.width = data_shape(1);
                    movie.height= data_shape(2);
                    
                    movie.data_depth = 8;  %this is number of bytes 8 or 16
                    %movie.data_depth = 16;  %this is number of bytes 8 or 16
                    %checking if the movie contains full or cropped frames
                    if (data_shape(3) == movie.width) && (data_shape(4) == movie.height)
                        movie.image_bytes = movie.width*movie.height;
                    else
                        movie.image_bytes = data_shape(3)*data_shape(4);            % this is if the image has been cropped
                        movie.width=data_shape(3);
                        movie.height=data_shape(4);
                    end
                    
                    if (movie.data_depth == 16)
                        movie.length_in_words = floor(movie.image_bytes/2); %each word is 2 bytes;
                    elseif (movie.data_depth == 8)
                        movie.length_in_words = movie.image_bytes;
                    else
                        fprintf('data neither 8 not 16 bit - not programmed for this.\n');
                        return;
                    end
                    
            end
            fseek(fid, 0, 'eof');
            file_size = ftell(fid) ;
            
            %position at the begining of the binary header+frame data
            fseek( fid, movie.offset_header , -1 );
            
            nn = (file_size - movie.offset_header) / (movie.length_header + movie.length_data);
            if (floor(nn) ~= nn)
                fprintf('something is wrong in the calculation nn needs to be an integer \n');
            end
            
            movie.NumFrames=double(nn);
            fclose(fid);
            
        end
        
        function IM=get(movie,varargin)
            % Function that loads frames contained in the movie
            % movie is a moviereader object, previously created 
            %
            % USAGE: frames=movie.get;              -load all the frames
            %        frames=movie.get(num);         -load the nth frame
            %        frames=movie.get([num1,num2]); -load the frames num1:num2
            %
            % ALT. USAGE: frames=get(movie);
            %             frames=get(movie,num);
            %             frames=get(movie,[num1,num2]);
            %
            %optional input parameter: frames to be loaded
            if nargin==2
                range=varargin{1};
                if length(range)>2;
                    disp('Connot load non contiguous frames. Call load iteratively');
                    return
                end
            elseif nargin==1;
                range=[1,movie.NumFrames];
            end
            
            if length(range)==2
                if range(2)>movie.NumFrames
                    disp(['The video contains ',num2str(movie.NumFrames),' frames only'])
                    range(2)=movie.NumFrames;
                end
            elseif length(range)==1
                if range(1)>movie.NumFrames
                    disp(['The video contains ',num2str(movie.NumFrames),' frames only'])
                    range(1)=movie.NumFrames;
                end
            end
            
            % bytes to skip
            offset=movie.offset_header+ (range(1)-1) * (movie.length_header + movie.length_data);
            
            if length(range)>1
                N_frames_to_load=diff(range)+1;
            else
                N_frames_to_load=1;
            end
            
            fmap=memmapfile([movie.Directory,movie.Filename],...
                'Offset', offset,...
                'Format', {'uint8' double([1, movie.length_header]) 'info';
                           ['uint',int2str(movie.data_depth)] double([movie.width, movie.height]) 'IM'},...                     
                'Repeat', N_frames_to_load);
            %keeping only the images
            data=fmap.data;
            clear fmap
            IM=[data.IM];
            clear data 
            
            %reshaping the image vector
            IM=reshape(IM,movie.width,movie.height,N_frames_to_load);
            
            if size(IM,3)==1;
                IM=squeeze(IM);
            end

            
        end
        
        
    end
    
    
end
