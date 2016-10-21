
% wrote to open the .czi and .lif files from Zeiss and Leica confocal microscope. The class
% returns some of the important metadata. Framerate is calculated using the
% timestamps of all the frames. Needs the bioformat library 5.1.10

classdef bioreader < handle
    
    % movie properties and data
    properties
        Directory % The subdirectory that contains the video
        Filename  % The filename of the video
        NumberOfFrames
        NumberOfImages
        size_T % The number of frames contained in the video
        size_Z % The number of frames contained in the video
        size_C % The number of frames contained in the video
        FrameRate % The number of frames recorded in a second
        width     % The image width, in pixels
        height    % The image height, in pixels
        info
        dpix
        dpix_zoom
        planeSize
        numSeries
        pixtype
        ZCT
        CSlice=0;
        meta
        pinhole
    end
    
    methods
        function movie=bioreader(moviename,varargin)
            % Function that loads the video and initialize its
            % structure, extracting the infos stored into the header of the
            % movie file.
            %
            % USAGE: movie = zeissfreader(filename);
            %        movie = zeissreader(filename,directory);
            
            %addpath 'matlab_leica/'        % add the path with the
            %bioformat files - the version 5.1.0
            
            datadir='';
            if nargin>1
                if ~isnumeric(varargin{1})
                    datadir=varargin{1};
                    if ~strcmp(datadir(end),'/');
                        datadir=[datadir,'/'];
                    end
                end
            end
            
            movie.Directory=datadir;
            movie.Filename=moviename;
          
            autoloadBioFormats = 1;
            
            % Toggle the stitchFiles flag to control grouping of similarly
            % named files into a single dataset based on file numbering.
            stitchFiles = 0;
            
            
            % load the Bio-Formats library into the MATLAB environment
            status = bfCheckJavaPath(autoloadBioFormats);
            assert(status, ['Missing Bio-Formats library. Either add loci_tools.jar '...
                'to the static Java path or add it to the Matlab path.']);
            
            % initialize logging
            loci.common.DebugTools.enableLogging('INFO');
            
            % Get the channel filler
            movie.info = bfGetReader([movie.Directory,movie.Filename], stitchFiles);
            
            movie.pixtype = movie.info.getPixelType();
            
            % organizing metadata
            %all=movie.info.getMetadataStore;
            %key_str=all.keySet.toString.toCharArray';
            %val_str=all.values.toString.toCharArray';

            movie.planeSize = loci.formats.FormatTools.getPlaneSize(movie.info);
            if movie.planeSize/(1024)^3 >= 2,
                error(['Image plane too large. Only 2GB of data can be extracted '...
                    'at one time. You can workaround the problem by opening '...
                    'the plane in tiles.']);
            end
            
            movie.numSeries = movie.info.getSeriesCount;

        end
        
        function movie=setSerie(movie,NSERIE,zoom,varargin)
            
            movie.info.setSeries(NSERIE-1);
            movie.size_T=movie.info.getSizeT;
            movie.size_Z=movie.info.getSizeZ;
            movie.size_C=movie.info.getSizeC;
            movie.width=round(movie.info.getSizeY*zoom);
            movie.height=round(movie.info.getSizeX*zoom);
            
            movie.NumberOfImages=movie.info.getImageCount;
            
            for k=0:movie.NumberOfImages-1
                movie.ZCT(k+1,:)=movie.info.getZCTCoords(k);
            end
            
            if nargin==4
                movie.CSlice=varargin{1};
            end
            
            if movie.size_T>movie.size_Z
                movie.NumberOfFrames=movie.size_T;
            else
                movie.NumberOfFrames=movie.size_Z;
            end
            
            dpixXAll = movie.info.getMetadataStore.getPixelsPhysicalSizeX(0);
            dpixX = dpixXAll.value;
            dpixYAll = movie.info.getMetadataStore.getPixelsPhysicalSizeY(0);
            dpixY = dpixYAll.value;
            
            if dpixX ~= dpixY
               disp('The size of the pixels in X and Y are different')
               pause
            else
                movie.dpix = double(dpixX);
            end
            
            % to find the frame rate I get the timestamp of each plane
            timestampi = NaN(1,movie.NumberOfFrames);
            for i = 1:movie.NumberOfFrames
                timestamp = movie.info.getMetadataStore.getPlaneDeltaT(NSERIE-1,i-1);
                timestampi(i) = double(timestamp.value);
            end
            
            movie.FrameRate = 1./(nanmean(diff(timestampi)));

        end
        
        
        function IM=read(movie,varargin)
            % Function that loads frames contained in the movie
            % movie is a moviereader object, previously created
            %
            % USAGE: frames=movie.read;              -load all the frames
            %        frames=movie.read(num);         -load the nth frame
            %        frames=movie.read([num1,num2]); -load the frames num1:num2
            %
            % ALT. USAGE: frames=read(movie);
            %             frames=read(movie,num);
            %             frames=read(movie,[num1,num2]);
            %
            %optional input parameter: frames to be loaded
            
            if nargin==2
                range=varargin{1};
                if length(range)>2;
                    disp('I cannot load non contiguous frames. Call load iteratively');
                    return
                end
            elseif nargin==1;
                range=[1,movie.NumberOfFrames];
            end
            
            if length(range)==2
                if range(2)>movie.NumberOfFrames
                    disp(['The video contains ',num2str(movie.NumberOfFrames),' frames only'])
                    range(2)=movie.NumberOfFrames;
                end
            elseif length(range)==1
                if range(1)>movie.NumberOfFrames
                    disp(['The video contains ',num2str(movie.NumberOfFrames),' frames only'])
                    range(1)=movie.NumberOfFrames;
                end
            end
            
            absoluterange=find(movie.ZCT(:,2)==movie.CSlice);
            
            if movie.height<movie.width
                
                if length(range)>1
                    rr=range(1):range(2);
                    IM=zeros(movie.height,movie.height,rr(2)-rr(1)+1);
                else
                    rr=range;
                    IM=zeros(movie.height,movie.height,1);
                end
            else
                if length(range)>1
                    rr=range(1):range(2);
                    IM=zeros(movie.width,movie.height,rr(2)-rr(1)+1);
                else
                    rr=range;
                    IM=zeros(movie.width,movie.height,1);
                end
            end
            
            j=0;
            
            %             ga=fspecial('gaussian',round(movie.height/20),round(movie.height/200));
            %             gas=fspecial('gaussian',13,5);
            
            for i = rr
                j=j+1;
                foo = double(bfGetPlane(movie.info, absoluterange(i)));
                

                if movie.height<movie.width
                    
                    foo=imresize(foo,[movie.height,movie.height],'cubic','antialiasing',true);
                    foo=((foo-min(foo(:)))./(max(foo(:))-min(foo(:)))*255);
                    movie.width=movie.height;
                    size(foo)
                else
                    foo=imresize(foo,[movie.width,movie.height],'cubic','antialiasing',true);
                    foo=((foo-min(foo(:)))./(max(foo(:))-min(foo(:)))*255);
                end
                
                IM(:,:,j)=single(foo);
                
            end
            
            IM=squeeze(IM);
        end
        
    end
end
