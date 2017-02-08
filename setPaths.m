function paths = setPaths()

paths.amat.root = fileparts(mfilename('fullpath')); 

% data
paths.data             = fullfile(paths.amat.root, 'data');
paths.bsds500          = fullfile(paths.data,'BSDS500');
paths.bsds500gt        = fullfile(paths.bsds500, 'groundtruth');
paths.bsds500im        = fullfile(paths.bsds500, 'images');
paths.symmax500        = fullfile(paths.data, 'SYMMAX500');

% amat
paths.amat.output      = fullfile(paths.amat.root, 'output');

% spb-mil
paths.spbmil.root      = fullfile(paths.amat.root, 'external', 'spb-mil');
paths.spbmil.output    = fullfile(paths.spbmil.root, 'output');
paths.spbmil.models    = fullfile(paths.spbmil.output, 'models');
paths.spbmil.spectral  = fullfile(paths.spbmil.output, 'spectral');
paths.spbmil.plots     = fullfile(paths.spbmil.output, 'plots');


% TODO: maybe remove the following to reduce clutter?
% paths.bsds500gtTrain   = fullfile(paths.bsds500gt,'train');
% paths.bsds500gtTest    = fullfile(paths.bsds500gt,'test');
% paths.bsds500gtVal     = fullfile(paths.bsds500gt,'val');
% paths.bsds500imTrain   = fullfile(paths.bsds500,'images','train');
% paths.bsds500imTest    = fullfile(paths.bsds500,'images','test');
% paths.bsds500imVal     = fullfile(paths.bsds500,'images','val');
 
